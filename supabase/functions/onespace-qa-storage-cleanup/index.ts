// QA-ONLY one-time orphan cleanup. Production project is explicitly rejected.
// This deletes Storage bytes through the Storage API, NEVER by SQL metadata deletion.
// No user account, space, member, push registration, or preference is modified.
const env=(name:string)=>(Deno.env.get(name)??"").trim();
const reply=(status:number,body:unknown)=>new Response(JSON.stringify(body),{
  status,headers:{"content-type":"application/json","cache-control":"no-store"}
});
const allow=new Set(["onespace-activity-media","onespace-activity-voice",
  "onespace-memory-photos","onespace-note-images","onespace-trip-documents",
  "onespace-share-in"]);
Deno.serve(async(request)=>{
  if(request.method!=="POST")return reply(405,{error:"POST required"});
  const secret=env("ONESPACE_PUSH_CRON_SECRET");
  if(!secret||request.headers.get("x-onespace-push-secret")!==secret)
    return reply(401,{error:"Unauthorized"});
  const base=env("SUPABASE_URL");
  const service=env("SUPABASE_SERVICE_ROLE_KEY");
  if(!base.startsWith("https://ugwrpeduzyzrujkizqfo.supabase.co")||!service)
    return reply(503,{error:"QA-only environment check failed"});
  const headers={apikey:service,Authorization:"Bearer "+service,"content-type":"application/json"};
  const manifest=async()=>{
    const response=await fetch(base+"/rest/v1/rpc/qa_storage_cleanup_manifest_service",{
      method:"POST",headers,body:"{}"});
    if(!response.ok)throw Error("Live-content protection blocked cleanup: "+response.status);
    const rows=await response.json();
    if(!Array.isArray(rows))throw Error("Unexpected manifest format");
    return rows as Array<{bucket_id:string,object_path:string}>;
  };
  let initial:Array<{bucket_id:string,object_path:string}>;
  try{initial=await manifest();}
  catch(error){return reply(409,{error:String(error).slice(0,160)});}
  const out={candidates:initial.length,deleted:0,failed:0};
  for(const bucket of allow){
    let rows:Array<{bucket_id:string,object_path:string}>;
    try{rows=(await manifest()).filter(r=>r.bucket_id===bucket);}
    catch(error){return reply(409,{...out,error:String(error).slice(0,160)});}
    const paths=rows.map(r=>r.object_path).filter(path=>
      typeof path==="string"&&path.length>0&&path.length<500&&
      !path.includes("..")&&!path.startsWith("/"));
    out.failed+=rows.length-paths.length;
    for(let at=0;at<paths.length;at+=20){
      const batch=paths.slice(at,at+20);
      const response=await fetch(base+"/storage/v1/object/"+bucket,{
        method:"DELETE",headers,body:JSON.stringify({prefixes:batch})});
      if(response.ok){out.deleted+=batch.length;}
      else{out.failed+=batch.length;}
    }
  }
  return reply(out.failed>0?207:200,out);
});