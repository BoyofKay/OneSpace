// OneSpace R24 - service-only FCM HTTP v1 delivery.
// No app user can invoke this worker; missing credentials fail closed.
const json=(status:number,body:unknown)=>new Response(JSON.stringify(body),{
 status,headers:{"content-type":"application/json","cache-control":"no-store"}});
const env=(key:string)=>Deno.env.get(key)?.trim()??"";
function base64url(bytes:Uint8Array):string{
 let result="";for(const b of bytes)result+=String.fromCharCode(b);
 return btoa(result).replaceAll("+","-").replaceAll("/","_").replaceAll("=","");
}
function bytes(input:string):Uint8Array{
 return new TextEncoder().encode(input);
}
async function googleAccessToken(account:{client_email:string,private_key:string}){
 const now=Math.floor(Date.now()/1000);
 const header=base64url(bytes(JSON.stringify({alg:"RS256",typ:"JWT"})));
 const claims=base64url(bytes(JSON.stringify({
  iss:account.client_email,scope:"https://www.googleapis.com/auth/firebase.messaging",
  aud:"https://oauth2.googleapis.com/token",iat:now,exp:now+3300,
 })));
 const base=header+"."+claims;
 const body=account.private_key.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g,"");
 const pem=atob(body);
 const raw=new Uint8Array(pem.length);for(let i=0;i<pem.length;i++)raw[i]=pem.charCodeAt(i);
 const key=await crypto.subtle.importKey("pkcs8",raw,
  {name:"RSASSA-PKCS1-v1_5",hash:"SHA-256"},false,["sign"]);
 const signature=new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5",key,bytes(base)));
 const token=base+"."+base64url(signature);
 const result=await fetch("https://oauth2.googleapis.com/token",{
  method:"POST",headers:{"content-type":"application/x-www-form-urlencoded"},
  body:new URLSearchParams({grant_type:"urn:ietf:params:oauth:grant-type:jwt-bearer",assertion:token}),
 });
 if(!result.ok)throw new Error("Firebase OAuth token request failed: "+result.status);
 const data=await result.json();
 if(typeof data.access_token!=="string")throw new Error("Firebase OAuth did not supply token");
 return data.access_token as string;
}
async function dbRpc<T>(url:string,key:string,method:string,args:object):Promise<T>{
 const result=await fetch(url+"/rest/v1/rpc/"+method,{
  method:"POST",headers:{apikey:key,Authorization:"Bearer "+key,
   "content-type":"application/json"},
  body:JSON.stringify(args),
 });
 if(!result.ok)throw new Error("Push database operation failed: "+method+" ("+result.status+")");
 return await result.json() as T;
}
type Delivery={delivery_id:string,registration_token:string,notification_id:string};
Deno.serve(async(req)=>{
 if(req.method!=="POST")return json(405,{error:"POST required"});
 const secret=env("ONESPACE_PUSH_CRON_SECRET");
 if(!secret)return json(503,{error:"Push worker not yet configured"});
 if(req.headers.get("x-onespace-push-secret")!==secret)
  return json(401,{error:"Unauthorized"});
 const dbUrl=env("SUPABASE_URL"),dbKey=env("SUPABASE_SERVICE_ROLE_KEY");
 const credentials=env("ONESPACE_FIREBASE_SERVICE_ACCOUNT_JSON");
 if(!dbUrl||!dbKey||!credentials)
  return json(503,{error:"Push credentials have not been configured"});
 let account:{project_id:string,client_email:string,private_key:string};
 try{
  account=JSON.parse(credentials);
  if(!account.project_id||!account.client_email||!account.private_key)
   throw Error("Missing credential field");
 }catch(_){return json(503,{error:"Firebase service credentials are invalid"});}
 let access:string;
 try{access=await googleAccessToken(account);}
 catch(_){return json(503,{error:"Firebase authorization unavailable"});}
 let batch:Delivery[];
 try{batch=await dbRpc<Delivery[]>(dbUrl,dbKey,"claim_push_outbox",{p_limit:25});}
 catch(_){return json(503,{error:"Push outbox unavailable"});}
 let sent=0,retried=0,invalid=0;
 for(const task of batch){
  let result:"sent"|"retry"|"invalid"="retry",reason="";
  try{
   const response=await fetch(
    "https://fcm.googleapis.com/v1/projects/"+encodeURIComponent(account.project_id)+"/messages:send",{
    method:"POST",headers:{"content-type":"application/json",Authorization:"Bearer "+access},
    body:JSON.stringify({message:{
     token:task.registration_token,
     notification:{title:"OneSpace",body:"You have a new update in your shared space."},
     data:{type:"notification",notification_id:task.notification_id},
     android:{priority:"high"},
    }}),
   });
   if(response.ok){result="sent";sent++;}
   else{
    // Only retire a device when FCM actually reports an unregistered token.
    const error=await response.json().catch(()=>({}));
    const details=Array.isArray(error?.error?.details)?error.error.details:[];
    const isUnregistered=details.some((x:Record<string,unknown>)=>
      x.errorCode==="UNREGISTERED")||error?.error?.status==="UNREGISTERED";
    if(isUnregistered){result="invalid";invalid++;}
    else{result="retry";retried++;}
    reason="FCM status "+response.status;
   }
  }catch(_){result="retry";retried++;reason="FCM network unavailable";}
  try{await dbRpc(dbUrl,dbKey,"complete_push_delivery",{
   p_delivery:task.delivery_id,p_result:result,p_error:reason,
  });}
  catch(_){/* Lease expires for safe retry if completion fails. */}
 }
 return json(200,{processed:batch.length,sent,retried,invalid});
});
