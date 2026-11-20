// QA account deletion runner, new policy safety gate (2026-11-20).
//
// The old worker retained couple-shared content while deleting a user. That
// behavior is FORBIDDEN. The new rule is: after 7 days (unless cancelled),
// delete the requesting user's personal content, all current couple-shared
// content, and their account, while preserving the survivor's personal scope
// and leaving them unpaired. Until the atomically safe, 22-root + dependent
// purge transaction is deployed and verified, NEVER run the legacy worker.
// A no-op at an unsafe deadline is reported as BLOCKED, not "deleted".
const env=(key:string)=>(Deno.env.get(key)??"").trim();
const json=(status:number,data:Record<string,unknown>)=>
  new Response(JSON.stringify(data),{status,headers:{
    "content-type":"application/json","cache-control":"no-store",
    "x-content-type-options":"nosniff",
  }});
Deno.serve(async(req:Request)=>{
  if(req.method!=="POST")return json(405,{error:"POST required"});
  const key=env("ONESPACE_PUSH_CRON_SECRET");
  if(!key||req.headers.get("x-onespace-push-secret")!==key)
    return json(401,{error:"Unauthorized"});
  const base=env("SUPABASE_URL"),service=env("SUPABASE_SERVICE_ROLE_KEY");
  if(!base||!service||new URL(base).hostname!=="ugwrpeduzyzrujkizqfo.supabase.co")
    return json(503,{error:"QA-only account deletion service unavailable"});
  let due:unknown;
  try{
    const r=await fetch(base+"/rest/v1/rpc/purge_due_accounts_list",{
      method:"POST",headers:{
        apikey:service,Authorization:"Bearer "+service,
        "content-type":"application/json"
      },body:"{}",
    });
    if(!r.ok)throw new Error("Account deletion registry unavailable");
    due=await r.json();
  }catch{return json(503,{error:"Unable to read account deletion schedule"});}
  if(!Array.isArray(due))
    return json(503,{error:"Invalid deletion schedule result"});
  if(due.length>0){
    console.error("Account purge blocked pending new private/shared ownership cutover",due.length);
    return json(503,{
      error:"Account purge not enabled: new privacy-preserving deletion is not verified",
      due_accounts_blocked:due.length,
      accounts_deleted:0,
    });
  }
  return json(200,{
    due_accounts:0,accounts_deleted:0,
    policy:"seven_day_grace_delete_account_and_shared_keep_survivor_private",
    mode:"fail_closed_until_new_data_purge_verified"
  });
});
