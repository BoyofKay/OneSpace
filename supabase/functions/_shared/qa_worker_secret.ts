// QA worker authentication without dashboard secrets: the scheduler sends the
// Vault-held secret; the database (service role only) confirms it matches.
// Fails closed on any error.
// deno-lint-ignore no-explicit-any
export async function qaVaultSecretMatches(db:any,name:string,presented:string|null):Promise<boolean>{
 if(!presented||presented.length<32)return false;
 try{
  const {data,error}=await db.rpc("qa_worker_secret_matches",{p_name:name,p_value:presented});
  return !error&&data===true;
 }catch{return false;}
}
