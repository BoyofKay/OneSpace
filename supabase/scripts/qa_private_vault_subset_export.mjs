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
