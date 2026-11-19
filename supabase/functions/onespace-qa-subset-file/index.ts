// QA-only 24h STORAGE staging for locally encrypted .osa vault-subset files.
// Validates actual ciphertext bytes and private Storage readback before
// download; never issues a trusted/complete archive or enables restoration.
const QA_HOST="ugwrpeduzyzrujkizqfo.supabase.co";
const MAX_FILE=20*1024*1024;
const MAX_CIPHER=12*1024*1024+16;
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SHA=/^[0-9a-f]{64}$/;
const env=(key:string)=>(Deno.env.get(key)??"").trim();
const noStore={"cache-control":"private, no-store, max-age=0",
 "x-content-type-options":"nosniff"};
const json=(status:number,value:Record<string,unknown>)=>
 new Response(JSON.stringify(value),{
  status,headers:{...noStore,"content-type":"application/json"}
 });
const hash=async(data:Uint8Array)=>
 Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256",data)),
   b=>b.toString(16).padStart(2,"0")).join("");
const safePath=(owner:string,id:string,path:string)=>
 path===owner+"/qa-subsets/"+id+".osa"&&!path.includes("..");
const storagePath=(path:string)=>
 path.split("/").map(encodeURIComponent).join("/");
const bearerHeaders=(key:string)=>({apikey:key,authorization:"Bearer "+key});
async function readBounded(body:ReadableStream<Uint8Array>,limit:number){
 const chunks:Uint8Array[]=[];
 let received=0;
 const reader=body.getReader();
 try{
  while(true){
   const {done,value}=await reader.read();
   if(done)break;
   received+=value.byteLength;
   if(received>limit){
    await reader.cancel();
    throw new Error("File too large");
   }
   chunks.push(value);
  }
 }finally{reader.releaseLock();}
 const content=new Uint8Array(received);
 let offset=0;
 for(const chunk of chunks){content.set(chunk,offset);offset+=chunk.length;}
 return content;
}
async function serviceRpc(base:string,service:string,name:string,body:object){
 const res=await fetch(base+"/rest/v1/rpc/"+name,{
  method:"POST",headers:{
    ...bearerHeaders(service),"content-type":"application/json"
  },body:JSON.stringify(body)
 });
 if(!res.ok)throw new Error("QA staging registry RPC failed");
 return res.json();
}
async function readStored(
 base:string,key:string,owner:string,id:string,path:string,
 bytes:number,digest:string
){
 if(!UUID.test(owner)||!UUID.test(id)||!safePath(owner,id,path)
  ||!Number.isSafeInteger(bytes)||bytes<1||bytes>MAX_FILE
  ||!SHA.test(digest))throw new Error("Invalid staged file metadata");
 const res=await fetch(base+"/storage/v1/object/authenticated/onespace-archives/"+
   storagePath(path),{headers:{...bearerHeaders(key),"cache-control":"no-store"}});
 if(!res.ok||!res.body)throw new Error("Private staged object unavailable");
 const stated=res.headers.get("content-length");
 if(stated!==null&&Number(stated)!==bytes)
  throw new Error("Stored ciphertext size differs from registry");
 const output=await readBounded(res.body,bytes);
 if(output.length!==bytes||await hash(output)!==digest)
  throw new Error("Stored ciphertext digest does not match registry");
 return output;
}
async function validateOpaqueFile(file:Uint8Array,owner:string,space:string){
 let envelope:Record<string,unknown>;
 try{
  envelope=JSON.parse(new TextDecoder("utf-8",{fatal:true}).decode(file));
 }catch{throw new Error("Invalid encrypted envelope")}
 if(!envelope||typeof envelope!=="object"||Array.isArray(envelope)
    ||envelope.format!=="onespace.qa.vault-subset.osa.v1"
    ||envelope.kind!=="qa-private-vault-subset"
    ||envelope.owner_id!==owner||envelope.source_space_id!==space
    ||envelope.all_69_types_packaged!==false
    ||envelope.server_signed!==false
    ||envelope.is_verified_archive!==false
    ||envelope.can_restore!==false||envelope.safe_to_separate!==false
    ||envelope.cipher!=="AES-256-GCM"
    ||envelope.kdf!=="PBKDF2-HMAC-SHA256"
    ||envelope.iterations!==600000
    ||typeof envelope.ciphertext_sha256!=="string"
    ||!SHA.test(envelope.ciphertext_sha256)
    ||typeof envelope.subset_sha256!=="string"
    ||!SHA.test(envelope.subset_sha256)
    ||!Number.isSafeInteger(envelope.ciphertext_bytes)
    ||(envelope.ciphertext_bytes as number)<17
    ||(envelope.ciphertext_bytes as number)>MAX_CIPHER
    ||typeof envelope.ciphertext_b64!=="string")
    throw new Error("Unverified subset envelope");
 const b64=envelope.ciphertext_b64 as string;
 if(b64.length>Math.ceil(MAX_CIPHER/3)*4+4||b64.length%4!==0
   ||!/^[A-Za-z0-9+/]+={0,2}$/.test(b64))
   throw new Error("Invalid encrypted ciphertext encoding");
 let binary:string;
 try{binary=atob(b64)}catch{throw new Error("Corrupt ciphertext")}
 if(binary.length!==envelope.ciphertext_bytes)
  throw new Error("Incorrect ciphertext length");
 const ciphertext=Uint8Array.from(binary,x=>x.charCodeAt(0));
 if(await hash(ciphertext)!==envelope.ciphertext_sha256)
  throw new Error("Encrypted ciphertext checksum mismatch");
 return hash(file);
}
async function removeStagingObject(base:string,key:string,path:string){
 const res=await fetch(base+"/storage/v1/object/onespace-archives",{
  method:"DELETE",headers:{...bearerHeaders(key),"content-type":"application/json"},
  body:JSON.stringify({prefixes:[path]})
 });
 if(!res.ok)throw new Error("Staged object cleanup unavailable");
}
Deno.serve(async(req:Request)=>{
 if(req.method!=="POST")return json(405,{error:"POST required"});
 const base=env("SUPABASE_URL");
 const anon=env("SUPABASE_ANON_KEY");
 const service=env("SUPABASE_SERVICE_ROLE_KEY");
 if(!base||!anon||!service||
    new URL(base).hostname!==QA_HOST)
   return json(503,{error:"QA subset Storage unavailable"});
 const auth=req.headers.get("authorization")??"";
 if(!/^Bearer [^\s]+$/.test(auth))return json(401,{error:"Sign in required"});
 let owner:string;
 try{
  const me=await fetch(base+"/auth/v1/user",{
    headers:{apikey:anon,authorization:auth}
  });
  if(!me.ok)return json(401,{error:"Expired session"});
  const user=await me.json();
  owner=String(user.id??"");
  if(!UUID.test(owner))return json(401,{error:"Session unavailable"});
 }catch{return json(503,{error:"Auth verification unavailable"});}
 const url=new URL(req.url);
 const action=url.searchParams.get("action");
 if(action==="upload"){
  const space=url.searchParams.get("source_space_id")??"";
  if(!UUID.test(space)||req.headers.get("content-type")!=="application/octet-stream")
    return json(400,{error:"Invalid subset upload parameters"});
  const length=req.headers.get("content-length");
  if(length!==null&&Number(length)>MAX_FILE)
    return json(413,{error:"QA encrypted subset too large"});
  if(!req.body)return json(400,{error:"Missing encrypted file"});
  let file:Uint8Array,sha:string;
  try{
   file=await readBounded(req.body,MAX_FILE);
   if(file.length<100)throw new Error("Tiny file");
   sha=await validateOpaqueFile(file,owner,space);
  }catch{return json(409,{error:"Encrypted subset file integrity rejected"});}
  let reservation:Record<string,unknown>|null=null;
  try{
   reservation=await serviceRpc(base,service,"qa_subset_reserve_service",{
      p_owner:owner,p_space:space
   });
   const id=String(reservation?.staging_id??"");
   const path=String(reservation?.object_path??"");
   if(!UUID.test(id)||!safePath(owner,id,path)||
      reservation?.is_verified_archive!==false||
      reservation?.can_restore!==false)
    throw new Error("Invalid storage reservation");
   const stored=await fetch(base+"/storage/v1/object/onespace-archives/"+
     storagePath(path),{
      method:"POST",headers:{...bearerHeaders(service),
        "content-type":"application/octet-stream",
        "x-upsert":"false","cache-control":"no-store"},
      body:file
   });
   if(!stored.ok)throw new Error("Storage write failed");
   await readStored(base,service,owner,id,path,file.length,sha);
   const available=await serviceRpc(base,service,
     "qa_subset_mark_available_service",{
      p_id:id,p_sha256:sha,p_byte_length:file.length
   });
   if(available!==true)throw new Error("Storage availability not registered");
   return json(200,{staging_id:id,
    encrypted_sha256:sha,byte_length:file.length,
    verified_storage_bytes:true,expires_in_hours:24,
    is_verified_archive:false,can_restore:false,safe_to_separate:false
   });
  }catch{
   if(reservation){
    const id=String(reservation.staging_id??"");
    const path=String(reservation.object_path??"");
    if(UUID.test(id)&&safePath(owner,id,path)){
     try{await removeStagingObject(base,service,path);}catch{}
     try{await serviceRpc(base,service,
       "qa_subset_mark_failed_service",{p_id:id});}catch{}
    }
   }
   return json(409,{error:"Staging or readback verification failed"});
  }
 }
 if(action==="download"){
  const id=url.searchParams.get("staging_id")??"";
  if(!UUID.test(id))return json(400,{error:"Invalid staged file identifier"});
  try{
   const row=await serviceRpc(base,service,"qa_subset_lookup_service",{
      p_owner:owner,p_id:id
   }) as Record<string,unknown>|null;
   if(!row||row.owner_id!==owner||row.staging_id!==id||
      row.is_verified_archive!==false||row.can_restore!==false)
    return json(404,{error:"Private QA staged file unavailable"});
   const stored=await readStored(base,service,owner,id,
     String(row.object_path),Number(row.byte_length),
     String(row.ciphertext_sha256));
   return new Response(stored,{status:200,headers:{
    ...noStore,"content-type":"application/octet-stream",
    "content-length":String(stored.length),
    "content-disposition":
      'attachment; filename="OneSpace-QA-Subset-'+id+'.osa"',
    "x-onespace-sha256":row.ciphertext_sha256 as string,
    "x-onespace-unverified-subset":"true"
   }});
  }catch{return json(409,{error:"Staged ciphertext unavailable or altered"});}
 }
 return json(400,{error:"Unknown staging action"});
});
