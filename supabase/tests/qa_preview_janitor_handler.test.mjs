import assert from "node:assert/strict";
import {test} from "node:test";
const owner="11111111-2222-4333-8444-555555555555";
const pid="bbbbbbbb-2222-4333-8444-555555555555";
const path=owner+"/qa-previews/"+pid+".onespace-preview";
const env={
  SUPABASE_URL:"https://ugwrpeduzyzrujkizqfo.supabase.co",
  SUPABASE_SERVICE_ROLE_KEY:"fake-service-secret",
  ONESPACE_PUSH_CRON_SECRET:"fake-cron-secret"
};
let handler;
globalThis.Deno={env:{get:k=>env[k]},serve:fn=>{handler=fn}};
await import("../functions/onespace-archive-janitor/index.ts");
assert.equal(typeof handler,"function");
const request=(secret=env.ONESPACE_PUSH_CRON_SECRET)=>new Request(
  env.SUPABASE_URL+"/functions/v1/onespace-archive-janitor",{
    method:"POST",
    headers:secret?{"x-onespace-push-secret":secret}:{}
  });
function backend(opts={}){
  const calls=[];
  globalThis.fetch=async(url,init)=>{
    const address=String(url),method=init?.method||"GET";
    calls.push({address,method,body:init?.body});
    if(address.endsWith("/rpc/archives_due_for_purge_service")){
      return Response.json([]);
    }
    if(address.endsWith("/rpc/qa_previews_due_for_purge_service")){
      return Response.json(opts.due??[{preview_id:pid,object_path:path}]);
    }
    if(address.endsWith("/rpc/qa_preview_finish_purge_service")){
      return Response.json(true);
    }
    if(address.endsWith("/rpc/qa_subset_due_purge_service")){
      return Response.json(opts.subsetDue??[]);
    }
    if(address.endsWith("/rpc/qa_subset_finish_purge_service")){
      return Response.json(true);
    }
    if(address.endsWith("/storage/v1/object/onespace-archives")&&method==="DELETE"){
      return opts.storageFailure?Response.json({error:"Storage failure"},{status:500})
        :Response.json([]);
    }
    throw new Error("Unexpected janitor call: "+address);
  };
  return calls;
}
test("QA 24h preview Storage cleanup never mixes with 30d archives",async t=>{
  await t.test("expired preview removes only exact object and records purge",async()=>{
    const calls=backend();
    const response=await handler(request());
    assert.equal(response.status,200);
    const body=await response.json();
    assert.equal(body.examined,0);
    assert.equal(body.purged,0);
    assert.equal(body.preview_examined,1);
    assert.equal(body.preview_purged,1);
    assert.equal(body.preview_failed,0);
    const deleteCalls=calls.filter(c=>c.method==="DELETE");
    assert.equal(deleteCalls.length,1);
    assert.deepEqual(JSON.parse(deleteCalls[0].body).prefixes,[path]);
    assert.equal(calls.filter(c=>c.address.endsWith("/rpc/finish_archive_purge_service")).length,0);
    assert.equal(calls.filter(c=>c.address.endsWith("/rpc/qa_preview_finish_purge_service")).length,1);
  });
  await t.test("path injection is never passed to Storage deletion",async()=>{
    const calls=backend({due:[{preview_id:pid,
      object_path:owner+"/qa-previews/../outside.onespace-preview"}]});
    const body=await (await handler(request())).json();
    assert.equal(body.preview_failed,1);
    assert.equal(body.preview_purged,0);
    assert.equal(calls.some(c=>c.method==="DELETE"),false);
  });
  await t.test("Storage failure does not falsely mark preview purged",async()=>{
    const calls=backend({storageFailure:true});
    const body=await (await handler(request())).json();
    assert.equal(body.preview_failed,1);
    assert.equal(body.preview_purged,0);
    assert.equal(calls.some(c=>c.address.endsWith("qa_preview_finish_purge_service")),false);
  });
  await t.test("empty expired queue is safe",async()=>{
    const calls=backend({due:[]});
    const body=await (await handler(request())).json();
    assert.equal(body.preview_examined,0);
    assert.equal(body.preview_purged,0);
    assert.equal(calls.some(c=>c.method==="DELETE"),false);
  });
  await t.test("expired QA .osa subset removes exact owner-prefixed ciphertext, not real archives",async()=>{
    const id="dddddddd-2222-4333-8444-555555555555";
    const qaPath=owner+"/qa-subsets/"+id+".osa";
    const calls=backend({due:[],subsetDue:[{staging_id:id,object_path:qaPath}]});
    const body=await (await handler(request())).json();
    assert.equal(body.subset_examined,1);
    assert.equal(body.subset_purged,1);
    assert.equal(body.subset_failed,0);
    const deletes=calls.filter(c=>c.method==="DELETE");
    assert.deepEqual(JSON.parse(deletes[0].body).prefixes,[qaPath]);
    assert.equal(calls.some(c=>c.address.endsWith("/rpc/finish_archive_purge_service")),false);
    assert.equal(calls.some(c=>c.address.endsWith("/rpc/qa_subset_finish_purge_service")),true);
  });
  await t.test("QA subset path traversal never reaches object deletion",async()=>{
    const id="dddddddd-2222-4333-8444-555555555555";
    const calls=backend({due:[],subsetDue:[
      {staging_id:id,object_path:owner+"/qa-subsets/../real-archive.osa"}
    ]});
    const body=await (await handler(request())).json();
    assert.equal(body.subset_failed,1);
    assert.equal(body.subset_purged,0);
    assert.equal(calls.some(c=>c.method==="DELETE"),false);
  });
  await t.test("unauthorized caller cannot trigger janitor",async()=>{
    const calls=backend();
    const result=await handler(request("wrong-secret"));
    assert.equal(result.status,401);
    assert.equal(calls.length,0);
  });
});
