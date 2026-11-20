// QA-only deployed unscheduled Auth finalizer; explicit activation disabled.
// Must require BOTH QA DB gate and explicit second server-only activation.
// Called only by trusted scheduler after 7-day cancellation window, all
// relationships erased, and every Storage object fully removed via API.
import {createClient} from "npm:@supabase/supabase-js@2.58.0";
import {isAccountReadyForAuthDeletion,validAccountId}
  from "../_shared/qa_account_finalizer_contract.mjs";
import {qaVaultSecretMatches} from "../_shared/qa_worker_secret.ts";

const env=(k:string)=>(Deno.env.get(k)??"").trim();
const respond=(status:number,body:Record<string,unknown>)=>
 new Response(JSON.stringify(body),{status,headers:{
  "content-type":"application/json","cache-control":"no-store",
  "x-content-type-options":"nosniff",
 }});

Deno.serve(async(req:Request)=>{
 if(req.method!=="POST")return respond(405,{error:"POST required"});
 const url=env("SUPABASE_URL"),key=env("SUPABASE_SERVICE_ROLE_KEY");
 let target:URL;
 try{target=new URL(url);}catch{return respond(503,{error:"QA backend unavailable"});}
 if(target.protocol!=="https:"||
   target.hostname!=="ugwrpeduzyzrujkizqfo.supabase.co"||!key)
  return respond(503,{error:"QA-only project safety check failed"});

 const db=createClient(url,key,{
  auth:{persistSession:false,autoRefreshToken:false},
 });
 // Two server-side switches: the Vault activation flag (explicit second
 // activation) and the worker secret, both checked by the database.
 if(!await qaVaultSecretMatches(db,"onespace_qa_allow_auth_finalization",
   "ENABLED_AFTER_ACCEPTANCE_"+"QA_ACCOUNT_FINALIZER"))
  return respond(503,{error:"QA Auth finalizer remains disabled"});
 if(!await qaVaultSecretMatches(db,"onespace_qa_auth_finalizer_secret",
   req.headers.get("x-onespace-qa-auth-finalizer-secret")))
  return respond(401,{error:"Unauthorized"});
 let raw:unknown;
 try{raw=await req.json();}catch{return respond(400,{error:"Invalid request"});}
 const id=(raw&&typeof raw==="object"&&"user_id" in raw)
  ? (raw as {user_id:unknown}).user_id:null;
 if(!validAccountId(id))return respond(400,{error:"Valid account UUID required"});
 // 7-day due-user pipeline is idempotent. Each service RPC has its own
 // explicit QA database gate, due check, owner check and rollback rules:
 // 1. Remove only the current shared relationship; preserve partner private.
 // 2. Retire the requester's old solo account-created space.
 // 3. Snapshot own files for the separate Storage API deletion worker.
 // The first invocation will normally stop at readiness (HTTP 409) while
 // media jobs remain. Reinvocation after physical removal can finish Auth.
 const preparatory=[
  "qa_due_account_close_current_relationship",
  "qa_retire_due_account_legacy_solo",
  "qa_prepare_due_account_private_media",
 ];
 for(const operation of preparatory){
  try{
   const {error}=await db.rpc(operation,{p_user:id});
   if(error)throw Error("Service preparation failed");
  }catch{
   return respond(503,{error:"Account deletion preparation blocked by a safety prerequisite"});
  }
 }

 let readiness:unknown;
 try{
  const {data,error}=await db.rpc("qa_account_final_deletion_readiness",{
   p_user:id,
  });
  if(error)throw Error("Readiness RPC refused");
  readiness=data;
 }catch{return respond(503,{error:"Account finalizer backend gate closed"});}
 if(!isAccountReadyForAuthDeletion(readiness))
  return respond(409,{error:"Account cannot be removed until all dependencies and media are gone"});

 // Atomically scrub completed media metadata + set sticky processing.
 // This DB transaction takes the SAME per-user advisory lock as pairing and
 // cancellation. A second finalizer cannot claim the account again.
 // IMPORTANT: if Auth Admin fails, leave processing sticky for manual review.
 let claim:unknown;
 try{
  const {data,error}=await db.rpc("qa_claim_account_for_auth_finalization",{
   p_user:id,
  });
  if(error)throw Error("Account claim was refused");
  claim=data;
 }catch{
  return respond(503,{error:"Account finalization claim blocked; manual safety review may be required"});
 }
 const finalized=claim&&typeof claim==="object"
  ? claim as {claimed?:unknown;claim_id?:unknown;readiness?:unknown}:null;
 if(finalized?.claimed!==true ||
    !validAccountId(finalized?.claim_id) ||
    !isAccountReadyForAuthDeletion(finalized?.readiness)){
  // A claim may already be committed; do NOT blindly retry Auth deletion.
  return respond(503,{error:"Unexpected claim verification; manual review required"});
 }

 try{
  // Supabase Auth Admin API: delete user AND cascade account-private namespace.
  // The DB's NO ACTION owner/child constraints must already pass the verified
  // synthetic SQL deletion. Do not use this API before full acceptance tests.
  const {error}=await db.auth.admin.deleteUser(id as string);
  if(error)throw Error("Auth Admin deletion refused");
 }catch{
  return respond(503,{error:"Auth deletion failed; account requires review"});
 }
 return respond(200,{status:"deleted",environment:"qa_only"});
});
