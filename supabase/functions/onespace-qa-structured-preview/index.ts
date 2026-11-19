// QA-only owner-authenticated encrypted *preview* issue and download service.
// It cannot create space_archives, restore records or enable lifecycle actions.
// The creator's JWT (never service_role) fetches the private structured payload.
import {encryptPrivateStructuredPreview} from "../_shared/structured_archive_crypto.mjs";

const QA_REF="ugwrpeduzyzrujkizqfo";
const MAX_FILE_BYTES=5242880;
const env=(name:string)=>(Deno.env.get(name)??"").trim();
const noStore={"cache-control":"no-store","x-content-type-options":"nosniff"};
const json=(status:number,body:Record<string,unknown>)=>
  new Response(JSON.stringify(body),{status,headers:{...noStore,"content-type":"application/json"}});
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const hex=/^[0-9a-f]{64}$/;
const bytes=new TextEncoder();
const hash=async(data:Uint8Array)=>
  Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256",data)),
    x=>x.toString(16).padStart(2,"0")).join("");

const safePath=(owner:string,path:string)=>
  path.startsWith(owner+"/qa-previews/") &&
  new RegExp("^"+owner+"/qa-previews/[0-9a-f-]{36}\\.onespace-preview$","i").test(path) &&
  !path.includes("..");
const storagePath=(path:string)=>path.split("/").map(encodeURIComponent).join("/");
async function fetchVerifiedObject(
  base:string,key:string,owner:string,path:string,length:number,digest:string
):Promise<Uint8Array>{
  if(!uuid.test(owner)||!safePath(owner,path)||!hex.test(digest)||
     !Number.isSafeInteger(length)||length<1||length>MAX_FILE_BYTES)
    throw new Error("Invalid preview metadata");
  const res=await fetch(base+"/storage/v1/object/authenticated/onespace-archives/"+
    storagePath(path),{
      headers:{apikey:key,authorization:"Bearer "+key,"cache-control":"no-store"}});
  if(!res.ok||!res.body)throw new Error("Stored preview unavailable");
  const stated=res.headers.get("content-length");
  if(stated!==null && Number(stated)!==length)
    throw new Error("Stored preview size mismatch");
  const output=new Uint8Array(length);
  const reader=res.body.getReader();
  let offset=0;
  while(true){
    const {done,value}=await reader.read();
    if(done)break;
    if(offset+value.length>length){
      await reader.cancel();throw new Error("Stored preview exceeded verified size");
    }
    output.set(value,offset);
    offset+=value.length;
  }
  if(offset!==length)throw new Error("Stored preview was truncated");
  if(await hash(output)!==digest)throw new Error("Stored preview checksum mismatch");
  return output;
}
const headers=(key:string,bearer:string,service=false)=>
  ({apikey:key,authorization:service?"Bearer "+key:bearer,"content-type":"application/json"});
async function rpc(base:string,key:string,name:string,payload:Record<string,unknown>,
                   bearer:string,service=false){
  const response=await fetch(base+"/rest/v1/rpc/"+name,{
    method:"POST",headers:headers(key,bearer,service),body:JSON.stringify(payload)});
  if(!response.ok)throw new Error("QA preview RPC failed: "+name);
  return response.json();
}

Deno.serve(async(req:Request)=>{
  if(req.method!=="POST")return json(405,{error:"POST required"});
  const base=env("SUPABASE_URL");
  const pub=env("SUPABASE_ANON_KEY");
  const service=env("SUPABASE_SERVICE_ROLE_KEY");
  // An accidental Production deployment of this QA-only function must fail.
  if(!base || new URL(base).hostname!==QA_REF+".supabase.co" || !pub||!service)
    return json(503,{error:"QA preview service unavailable"});
  const bearer=req.headers.get("authorization")??"";
  if(!/^Bearer [^\s]+$/.test(bearer))return json(401,{error:"Sign in required"});

  let body:Record<string,unknown>;
  try{
    const raw=await req.text();
    if(raw.length>1600)return json(413,{error:"Request too large"});
    body=JSON.parse(raw);
    if(!body||typeof body!=="object"||Array.isArray(body))
      return json(400,{error:"Invalid preview request"});
  }catch{return json(400,{error:"Invalid preview request"});}
  if(body.action!=="issue" && body.action!=="download")
    return json(400,{error:"Invalid preview action"});

  let owner:string;
  try{
    const identity=await fetch(base+"/auth/v1/user",{
      headers:{apikey:pub,authorization:bearer}});
    if(!identity.ok)return json(401,{error:"Session expired"});
    const u=await identity.json();
    owner=String(u.id??"");
    if(!uuid.test(owner))return json(401,{error:"Session expired"});
  }catch{return json(503,{error:"Authentication unavailable"});}

  if(body.action==="download"){
    const id=body.preview_id;
    if(typeof id!=="string"||!uuid.test(id))
      return json(400,{error:"Invalid preview identifier"});
    try{
      const query=new URL(base+"/rest/v1/qa_structured_preview_staging");
      query.searchParams.set("select",
        "id,recipient_id,status,object_path,object_sha256,byte_length,expires_at,is_verified_archive,can_restore,verified_storage_bytes");
      query.searchParams.set("id","eq."+id);
      query.searchParams.set("recipient_id","eq."+owner);
      query.searchParams.set("limit","1");
      const res=await fetch(query,{headers:{apikey:pub,authorization:bearer}});
      if(!res.ok)return json(404,{error:"Preview unavailable"});
      const rows=await res.json();
      const record=rows?.[0];
      if(!record||record.recipient_id!==owner||record.status!=="available"||
         !record.verified_storage_bytes||record.is_verified_archive!==false||
         record.can_restore!==false||!record.expires_at||
         Date.parse(record.expires_at)<=Date.now())
        return json(404,{error:"Preview unavailable"});
      const sealed=await fetchVerifiedObject(base,service,owner,
        record.object_path,Number(record.byte_length),String(record.object_sha256));
      return new Response(sealed,{status:200,headers:{
        ...noStore,"content-type":"application/octet-stream",
        "content-disposition":'attachment; filename="OneSpace-QA-'+id+'.onespace-preview"',
        "content-length":String(sealed.length),"x-onespace-preview-only":"true",
        "x-onespace-sha256":record.object_sha256
      }});
    }catch{return json(409,{error:"Encrypted preview could not be verified"});}
  }

  if(!['shared_trips','tasks'].includes(String(body.source_table)) ||
     typeof body.source_id!=="string"||!uuid.test(body.source_id)||
     typeof body.passphrase!=="string"||
     body.passphrase.length<16||body.passphrase.length>256)
    return json(400,{error:"Invalid private preview parameters"});
  let preview:Record<string,any>;
  try{
    // These SECURITY INVOKER/owner-verified RPCs enforce original row access
    // with the real user JWT. Service credentials never read plaintext.
    preview=await rpc(base,pub,"qa_private_structured_package",{
      p_source_table:body.source_table,p_source_id:body.source_id
    },bearer);
    if(!preview?.payload||preview.payload.owner_id!==owner||
       preview.payload.root?.source_id!==body.source_id||
       preview.is_verified_archive!==false||preview.can_restore!==false)
      return json(403,{error:"Private preview unauthorized"});
  }catch{return json(404,{error:"Private preview unavailable"});}

  let sealed:Uint8Array, digest:string;
  try{
    const envelope=await encryptPrivateStructuredPreview(preview,body.passphrase);
    sealed=bytes.encode(JSON.stringify(envelope));
    if(sealed.length<1||sealed.length>MAX_FILE_BYTES)
      return json(413,{error:"Encrypted preview exceeds QA cap"});
    digest=await hash(sealed);
  }catch{return json(409,{error:"Structured preview is not eligible for encryption"});}

  let reservation:Record<string,any>|null=null;
  try{
    reservation=await rpc(base,service,"qa_preview_reserve_service",{
      p_owner:owner,p_space:preview.payload.source_space_id,
      p_source_table:body.source_table,p_source_id:body.source_id
    },bearer,true);
    if(!reservation||!uuid.test(String(reservation.preview_id))||
       !safePath(owner,String(reservation.object_path)))
      throw new Error("Invalid reservation");
    const path=String(reservation.object_path);
    const response=await fetch(base+"/storage/v1/object/onespace-archives/"+
      storagePath(path),{method:"POST",headers:{
        apikey:service,authorization:"Bearer "+service,
        "content-type":"application/octet-stream",
        "x-upsert":"false","cache-control":"no-store"
      },body:sealed});
    if(!response.ok)throw new Error("Encrypted object upload unavailable");
    await fetchVerifiedObject(base,service,owner,path,sealed.length,digest);
    const ok=await rpc(base,service,"qa_preview_mark_available_service",{
      p_id:reservation.preview_id,p_sha256:digest,p_byte_length:sealed.length
    },bearer,true);
    if(ok!==true)throw new Error("Preview not finalized");
    return json(201,{
      preview_id:reservation.preview_id,
      expires_at:reservation.expires_at,
      object_sha256:digest,
      byte_length:sealed.length,
      preview_only:true,is_verified_archive:false,can_restore:false,
      safe_to_separate:false
    });
  }catch{
    if(reservation?.preview_id && uuid.test(String(reservation.preview_id))){
      // Compensate partial operations. Never expose internal object paths.
      try{await rpc(base,service,"qa_preview_mark_failed_service",{
        p_id:reservation.preview_id
      },bearer,true);}catch{}
      if(safePath(owner,String(reservation.object_path))){
        try{await fetch(base+"/storage/v1/object/onespace-archives",{
          method:"DELETE",headers:headers(service,bearer,true),
          body:JSON.stringify({prefixes:[reservation.object_path]})
        });}catch{}
      }
    }
    return json(503,{error:"Encrypted QA preview could not be staged"});
  }
});
