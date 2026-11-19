// Mocked end-to-end QA archive *preview* issuer test, Node 22. Real handler
// and WebCrypto are exercised, without production access or persisted objects.
import assert from "node:assert/strict";
import {test} from "node:test";
import {createHash} from "node:crypto";
import {decryptPrivateStructuredPreview} from
  "../functions/_shared/structured_archive_crypto.mjs";

const base="https://ugwrpeduzyzrujkizqfo.supabase.co";
const owner="11111111-2222-4333-8444-555555555555";
const other="99999999-2222-4333-8444-555555555555";
const space="88888888-2222-4333-8444-555555555555";
const source="aaaaaaaa-2222-4333-8444-555555555555";
const previewId="bbbbbbbb-2222-4333-8444-555555555555";
const passphrase="An independent verified backup secret 2026!";
const objectPath=owner+"/qa-previews/"+previewId+".onespace-preview";
const sha=data=>createHash("sha256").update(data).digest("hex");
const original={
  payload:{
    schema:"onespace.private-task-checklist-preview.v1",
    owner_id:owner,source_space_id:space,
    root:{table:"tasks",source_id:source,
      structured:{id:source,created_by:owner,title:"Private family checklist",visibility:"private"}},
    children:{task_checklist_items:[
      {source_id:"cccccccc-2222-4333-8444-555555555555",
       structured:{title:"Remember our trip together",created_by:owner}}],task_checklist_checks:[]},
    child_record_count:1
  },
  media_included:false,documents_included:false,encrypted:false,
  is_verified_archive:false,can_restore:false,safe_to_separate:false
};
const env={
  SUPABASE_URL:base,
  SUPABASE_ANON_KEY:"test-publishable",
  SUPABASE_SERVICE_ROLE_KEY:"test-service"
};
let handler;
globalThis.Deno={env:{get:k=>env[k]},serve:fn=>{handler=fn}};
await import("../functions/onespace-qa-structured-preview/index.ts");
assert.equal(typeof handler,"function");
const request=(payload,bearer="Bearer signed-account-token")=>
  new Request(base+"/functions/v1/onespace-qa-structured-preview",{
    method:"POST",headers:bearer?{authorization:bearer}:{},
    body:JSON.stringify(payload)
  });
const issue=()=>request({action:"issue",source_table:"tasks",source_id:source,passphrase});
const download=(id=previewId)=>request({action:"download",preview_id:id});

function mockBackend(opts={}){
  const calls=[],objects=new Map();
  let record=null,failed=false;
  globalThis.fetch=async(input,options={})=>{
    const uri=String(input),method=options.method||"GET";
    calls.push({uri,method,headers:options.headers,body:options.body});
    if(uri.endsWith("/auth/v1/user")){
      return Response.json({id:owner});
    }
    if(uri.endsWith("/rest/v1/rpc/qa_private_structured_package")){
      return opts.ownerDenied?Response.json({error:"not owner"},{status:403}):
        Response.json(original);
    }
    if(uri.endsWith("/rest/v1/rpc/qa_preview_reserve_service")){
      return Response.json({
        preview_id:previewId,object_path:objectPath,
        expires_at:"2099-01-01T00:00:00Z"});
    }
    if(uri.endsWith("/rest/v1/rpc/qa_preview_mark_available_service")){
      const body=JSON.parse(options.body);
      const bytes=objects.get(objectPath);
      assert.equal(body.p_sha256,sha(bytes));
      assert.equal(body.p_byte_length,bytes.byteLength);
      record={
        id:previewId,recipient_id:owner,status:"available",
        expires_at:"2099-01-01T00:00:00Z",
        object_path:objectPath,object_sha256:sha(bytes),
        byte_length:bytes.byteLength,verified_storage_bytes:true,
        is_verified_archive:false,can_restore:false
      };
      return Response.json(true);
    }
    if(uri.endsWith("/rest/v1/rpc/qa_preview_mark_failed_service")){
      failed=true;return Response.json(true);
    }
    if(uri.includes("/rest/v1/qa_structured_preview_staging?")){
      return Response.json(record?[opts.forgedRecipient?
        {...record,recipient_id:other}:record]:[]);
    }
    if(uri.includes("/storage/v1/object/onespace-archives/") ||
       uri.endsWith("/storage/v1/object/onespace-archives")){
      if(method==="POST"){
        const path=decodeURIComponent(uri.split("/onespace-archives/")[1]);
        const bytes=new Uint8Array(options.body);
        objects.set(path,bytes);
        return Response.json({Key:path});
      }
      if(method==="DELETE"){
        for(const path of JSON.parse(options.body).prefixes)objects.delete(path);
        return Response.json([]);
      }
    }
    if(uri.includes("/storage/v1/object/authenticated/onespace-archives/")){
      const path=decodeURIComponent(uri.split("/onespace-archives/")[1]);
      const originalBytes=objects.get(path);
      if(!originalBytes)return Response.json({message:"missing"},{status:404});
      const altered=opts.tamperOnRead||false;
      const contents=new Uint8Array(originalBytes);
      if(altered)contents[12]^=9;
      if(opts.truncateOnRead) return new Response(contents.slice(0,-1));
      return new Response(contents,{headers:{"content-length":String(contents.length)}});
    }
    throw Error("Unmocked dependency: "+method+" "+uri);
  };
  return {calls,objects,get record(){return record},get failed(){return failed}};
}
test("QA preview issuer: full authenticated encrypted private Storage roundtrip",async t=>{
  await t.test("issue -> upload -> verify -> registry -> owner-only download -> decrypt",async()=>{
    const backend=mockBackend();
    const issued=await handler(issue());
    assert.equal(issued.status,201);
    const details=await issued.json();
    assert.equal(details.preview_id,previewId);
    assert.equal(details.preview_only,true);
    assert.equal(details.is_verified_archive,false);
    assert.equal(details.can_restore,false);
    assert.equal(details.safe_to_separate,false);
    assert.equal(details.object_sha256,sha(backend.objects.get(objectPath)));
    assert.equal(backend.record.status,"available");
    assert.equal(backend.record.is_verified_archive,false);
    const downloaded=await handler(download());
    assert.equal(downloaded.status,200);
    assert.equal(downloaded.headers.get("x-onespace-preview-only"),"true");
    const bytes=new Uint8Array(await downloaded.arrayBuffer());
    assert.equal(sha(bytes),details.object_sha256);
    const envelope=JSON.parse(new TextDecoder().decode(bytes));
    assert.equal(envelope.owner_id,owner);
    assert.equal(envelope.can_restore,false);
    const unsealed=await decryptPrivateStructuredPreview(envelope,passphrase,owner);
    assert.deepEqual(unsealed.payload,original.payload);
    assert.equal(unsealed.can_restore,false);
    assert.equal(backend.calls.filter(c=>c.uri.includes("/storage/v1/object/authenticated/")).length,2);
    assert.equal(backend.calls.filter(c=>c.uri.includes("rest/v1/rpc/qa_private_structured_package") &&
       c.headers.apikey==="test-service").length,0);
  });
  await t.test("partner-owned source is denied before encryption or reservation",async()=>{
    const backend=mockBackend({ownerDenied:true});
    const response=await handler(issue());
    assert.equal(response.status,404);
    assert.equal(backend.calls.filter(c=>c.uri.endsWith("qa_preview_reserve_service")).length,0);
  });
  await t.test("wrong passphrase does not decrypt a valid preview",async()=>{
    mockBackend();
    assert.equal((await handler(issue())).status,201);
    const response=await handler(download());
    const envelope=JSON.parse(await response.text());
    await assert.rejects(
      decryptPrivateStructuredPreview(envelope,"Definitely the wrong passphrase",owner),
      /decryption or authentication failed/);
  });
  await t.test("same-sized Storage tamper on issue triggers failed reservation and object removal",async()=>{
    const backend=mockBackend({tamperOnRead:true});
    assert.equal((await handler(issue())).status,503);
    assert.equal(backend.failed,true);
    assert.equal(backend.objects.size,0);
  });
  await t.test("wrong partner registry is rejected without fetching Storage",async()=>{
    const backend=mockBackend({forgedRecipient:true});
    // Populate backend once, then simulate malicious replacement in metadata.
    assert.equal((await handler(issue())).status,201);
    assert.equal((await handler(download())).status,404);
    assert.equal(backend.calls.filter(c=>c.uri.includes("/storage/v1/object/authenticated/")).length,1);
  });
  await t.test("truncated Storage response blocks download with integrity error",async()=>{
    const backend=mockBackend();
    assert.equal((await handler(issue())).status,201);
    backend.objects.set(objectPath,backend.objects.get(objectPath).slice(0,-1));
    assert.equal((await handler(download())).status,409);
  });
  await t.test("anonymous, malformed and unsupported calls reject before Storage",async()=>{
    const backend=mockBackend();
    assert.equal((await handler(request({action:"issue"},null))).status,401);
    assert.equal((await handler(request({action:"issue",source_table:"notes",
        source_id:source,passphrase}))).status,400);
    assert.equal((await handler(download("invalid"))).status,400);
    assert.equal(backend.calls.filter(c=>c.uri.includes("/storage/")).length,0);
  });
  await t.test("function refuses accidental Production deployment",async()=>{
    const original=env.SUPABASE_URL;
    try{
      env.SUPABASE_URL="https://letcgxbnblohhfyeuigz.supabase.co";
      assert.equal((await handler(issue())).status,503);
    }finally{env.SUPABASE_URL=original;}
  });
});
