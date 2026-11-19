// QA-only authenticated local export. No service-role key, no database writes.
// The passphrase never travels to Supabase. This only covers the verified
// 14 private root + 9 private dependent vault-snapshot families.
import {writeFile} from "node:fs/promises";
import {createHash} from "node:crypto";
import {encryptVaultSubsetFile,decryptVaultSubsetFile} from
 "../functions/_shared/qa_vault_subset_osa.mjs";

const QA_HOST="ugwrpeduzyzrujkizqfo.supabase.co";
const MAX_RPC_RESPONSE=16*1024*1024;
const fail=()=>{throw new Error("QA archive RPC export rejected")};
function qaUrl(raw){
 let u;
 try{u=new URL(raw)}catch{fail()}
 if(u.protocol!=="https:"||u.hostname!==QA_HOST||u.username||
    u.password||u.port||u.pathname!=="/"||u.search||u.hash)fail();
 return "https://"+QA_HOST;
}
async function limitedJson(response){
 if(!response?.ok)fail();
 if(Number(response.headers?.get("content-length"))>MAX_RPC_RESPONSE)fail();
 if(!response.body?.getReader)fail();
 const reader=response.body.getReader();
 let sum=0,chunks=[];
 try{
  while(true){
   const {done,value}=await reader.read();
   if(done)break;
   sum+=value.length;
   if(sum>MAX_RPC_RESPONSE)fail();
   chunks.push(value);
  }
 }finally{
  reader.releaseLock();
 }
 const total=new Uint8Array(sum);
 let i=0;
 for(const part of chunks){total.set(part,i);i+=part.length;}
 let parsed;
 try{parsed=JSON.parse(new TextDecoder("utf-8",{fatal:true}).decode(total))}
 catch{fail()}
 if(!parsed||typeof parsed!=="object"||Array.isArray(parsed))fail();
 return parsed;
}
export async function exportQaPrivateVaultSubset({
 url,anonKey,accessToken,passphrase,destination,fetchImpl=fetch,
 writeFileImpl=writeFile
}){
 const base=qaUrl(url);
 if(typeof anonKey!=="string"||anonKey.length<12||
    typeof accessToken!=="string"||accessToken.length<24||
    typeof destination!=="string"||!destination.endsWith(".osa")
    ||destination.length>1024)fail();
 const response=await fetchImpl(
  base+"/rest/v1/rpc/qa_private_vault_subset_manifest",
  {method:"POST",headers:{
    "Content-Type":"application/json",
    apikey:anonKey,
    Authorization:"Bearer "+accessToken
  },body:"{}"}
 );
 const manifest=await limitedJson(response);
 // encryptVaultSubsetFile will verify every source JSON byte hash, root
 // owner, original relationship space and private child lineage.
 const encrypted=await encryptVaultSubsetFile(manifest,passphrase);
 await writeFileImpl(destination,encrypted,{flag:"wx",mode:0o600});
 return {destination,encrypted_bytes:encrypted.length,
   encrypted_sha256:createHash("sha256").update(encrypted).digest("hex"),
   source_record_count:manifest.record_count,
   source_subset_sha256:manifest.subset_sha256,
   is_complete_onespace_archive:false,can_restore:false};
}
export async function verifyLocalQaSubsetFile({
 archiveBytes,passphrase,ownerId,spaceId
}){
 return decryptVaultSubsetFile(archiveBytes,passphrase,ownerId,spaceId);
}

const QA_SUBSET_FILE_MAX=20*1024*1024;
const UUID=/^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i;
async function responseBytes(response,max=QA_SUBSET_FILE_MAX){
 if(!response?.ok||!response.body?.getReader)fail();
 const declared=response.headers.get("content-length");
 if(declared!==null&&Number(declared)>max)fail();
 const reader=response.body.getReader();
 let size=0,parts=[];
 try{
   while(true){
     const {value,done}=await reader.read();
     if(done)break;
     size+=value.byteLength;
     if(size>max){await reader.cancel();fail();}
     parts.push(value);
   }
 }finally{reader.releaseLock();}
 const file=new Uint8Array(size);
 let offset=0;
 for(const part of parts){file.set(part,offset);offset+=part.length;}
 if(declared!==null&&Number(declared)!==size)fail();
 return file;
}
// Real QA-only ciphertext staging. Independently decrypts and checks every
// local record BEFORE uploading bytes, but NEVER uploads the passphrase.
export async function uploadQaPrivateVaultSubset({
 url,anonKey,accessToken,archiveBytes,passphrase,ownerId,spaceId,
 fetchImpl=fetch
}){
 const base=qaUrl(url);
 if(!UUID.test(ownerId)||!UUID.test(spaceId)
   ||typeof anonKey!=="string"||anonKey.length<12
   ||typeof accessToken!=="string"||accessToken.length<24
   ||!(archiveBytes instanceof Uint8Array)
   ||archiveBytes.length<100||archiveBytes.length>QA_SUBSET_FILE_MAX)fail();
 const evidence=await decryptVaultSubsetFile(
   archiveBytes,passphrase,ownerId,spaceId);
 if(evidence.can_restore!==false||
    evidence.verified_source_origin!==false)fail();
 const target=new URL(base+"/functions/v1/onespace-qa-subset-file");
 target.searchParams.set("action","upload");
 target.searchParams.set("source_space_id",spaceId);
 const result=await fetchImpl(target.toString(),{
   method:"POST",headers:{
     apikey:anonKey,Authorization:"Bearer "+accessToken,
     "content-type":"application/octet-stream"
   },body:archiveBytes
 });
 const details=await limitedJson(result);
 const actual=createHash("sha256").update(archiveBytes).digest("hex");
 if(!UUID.test(details.staging_id)
  ||details.encrypted_sha256!==actual
  ||details.byte_length!==archiveBytes.length
  ||details.verified_storage_bytes!==true
  ||details.is_verified_archive!==false
  ||details.can_restore!==false
  ||details.safe_to_separate!==false)fail();
 return {...details,verified_source_origin:false};
}
export async function downloadQaPrivateVaultSubset({
 url,anonKey,accessToken,stagingId,passphrase,ownerId,spaceId,
 fetchImpl=fetch
}){
 const base=qaUrl(url);
 if(!UUID.test(stagingId)||!UUID.test(ownerId)||!UUID.test(spaceId)
  ||typeof anonKey!=="string"||anonKey.length<12
  ||typeof accessToken!=="string"||accessToken.length<24)fail();
 const target=new URL(base+"/functions/v1/onespace-qa-subset-file");
 target.searchParams.set("action","download");
 target.searchParams.set("staging_id",stagingId);
 const response=await fetchImpl(target.toString(),{
   method:"POST",headers:{
     apikey:anonKey,Authorization:"Bearer "+accessToken
   }
 });
 if(response.headers.get("x-onespace-unverified-subset")!=="true")
   fail();
 const archiveBytes=await responseBytes(response);
 const digest=createHash("sha256").update(archiveBytes).digest("hex");
 if(response.headers.get("x-onespace-sha256")!==digest)fail();
 const verified=await decryptVaultSubsetFile(
   archiveBytes,passphrase,ownerId,spaceId);
 return {archiveBytes,verified_storage_transfer:true,
   verified_source_origin:false,can_restore:false,
   is_verified_archive:false,record_evidence:verified.evidence};
}
