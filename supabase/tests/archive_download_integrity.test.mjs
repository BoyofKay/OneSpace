// Node 22+ integration-style unit tests for the real QA Edge handler.
// Runs against mocked Auth/PostgREST/Storage responses; no real user data.
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { test } from "node:test";

const owner="11111111-2222-4333-8444-555555555555";
const archiveId="cccccccc-2222-4333-8444-aaaaaaaaaaaa";
const base="https://qa-archive.invalid";
const bytes=new TextEncoder().encode("onespace verified encrypted test fixture");
const sha=(data)=>createHash("sha256").update(data).digest("hex");
const env={
  SUPABASE_URL:base,
  SUPABASE_ANON_KEY:"test-publishable-key",
  SUPABASE_SERVICE_ROLE_KEY:"test-service-key"
};
let handler;
globalThis.Deno={
  env:{get:(key)=>env[key]},
  serve:(fn)=>{handler=fn}
};
await import("../functions/onespace-download-archive/index.ts");
assert.equal(typeof handler,"function");

const metadata=(options={})=>({
  id:archiveId,recipient_id:owner,status:"ready",archive_kind:"private",
  expires_at:"2099-01-01T00:00:00Z",
  encrypted_object_path:owner+"/verified-v1.onespace",
  encrypted_bytes_verified:true,
  ciphertext_sha256:sha(bytes),
  byte_length:bytes.byteLength,
  ...options
});
const request=(id=archiveId,method="POST",auth=true)=>new Request(base+"/functions/v1/onespace-download-archive",{
  method,
  headers:auth?{authorization:"Bearer test.jwt"}:{},
  ...(method==="POST"?{body:JSON.stringify({archive_id:id})}:{})
});
const setup=({record=metadata(),storageBytes=bytes,reportedLength=null,storageStatus=200}={})=>{
  const calls=[];
  globalThis.fetch=async (url,options)=>{
    const text=String(url);calls.push({url:text,authorization:options?.headers?.Authorization||null});
    if(text.endsWith("/auth/v1/user"))return Response.json({id:owner});
    if(text.includes("/rest/v1/space_archives"))return Response.json([record]);
    if(text.includes("/storage/v1/object/authenticated/")){
      const headers=reportedLength===null?{}:{"content-length":String(reportedLength)};
      return new Response(storageBytes,{status:storageStatus,headers});
    }
    throw new Error("Unexpected network call: "+text);
  };
  return calls;
};
test("actual archive bytes must match metadata SHA-256 before any download",async (t)=>{
  await t.test("valid ciphertext returns exact verified bytes",async()=>{
    const calls=setup();
    const response=await handler(request());
    assert.equal(response.status,200);
    assert.equal(response.headers.get("x-onespace-sha256"),sha(bytes));
    assert.deepEqual(new Uint8Array(await response.arrayBuffer()),bytes);
    assert.equal(calls.filter(x=>x.url.includes("/storage/v1/object/")).length,1);
  });
  await t.test("same-size altered ciphertext is rejected",async()=>{
    const corrupt=bytes.slice();corrupt[1]^=12;
    setup({storageBytes:corrupt,reportedLength:bytes.byteLength});
    const response=await handler(request());
    assert.equal(response.status,409);
    assert.equal(response.headers.get("x-onespace-sha256"),null);
  });
  await t.test("short Storage stream rejected without trusting missing length header",async()=>{
    setup({storageBytes:bytes.slice(0,bytes.length-1)});
    assert.equal((await handler(request())).status,409);
  });
  await t.test("oversized Storage stream rejected before digest",async()=>{
    const extra=new Uint8Array(bytes.length+1);extra.set(bytes);
    setup({storageBytes:extra});
    assert.equal((await handler(request())).status,409);
  });
  await t.test("inconsistent Content-Length rejected",async()=>{
    setup({reportedLength:bytes.length+1});
    assert.equal((await handler(request())).status,409);
  });
  await t.test("unverified registry record cannot fetch Storage",async()=>{
    const calls=setup({record:metadata({encrypted_bytes_verified:false})});
    assert.equal((await handler(request())).status,404);
    assert.equal(calls.some(x=>x.url.includes("/storage/v1/object/")),false);
  });
  await t.test("other account's archive cannot fetch Storage",async()=>{
    const calls=setup({record:metadata({recipient_id:"99999999-2222-4333-8444-555555555555"})});
    assert.equal((await handler(request())).status,404);
    assert.equal(calls.some(x=>x.url.includes("/storage/v1/object/")),false);
  });
  await t.test("nonowner Storage path rejected",async()=>{
    const calls=setup({record:metadata({encrypted_object_path:"99999999-2222-4333-8444-555555555555/x.onespace"})});
    assert.equal((await handler(request())).status,409);
    assert.equal(calls.some(x=>x.url.includes("/storage/v1/object/")),false);
  });
  await t.test("no bearer gets 401 without Auth lookup",async()=>{
    const calls=setup();
    assert.equal((await handler(request(archiveId,"POST",false)).status),401);
    assert.equal(calls.length,0);
  });
  await t.test("invalid archive identifier rejected without Storage lookup",async()=>{
    const calls=setup();
    assert.equal((await handler(request("not-a-uuid"))).status,400);
    assert.equal(calls.some(x=>x.url.includes("/storage/v1/object/")),false);
  });
  await t.test("GET is never accepted",async()=>{
    const calls=setup();
    assert.equal((await handler(request(archiveId,"GET"))).status,405);
    assert.equal(calls.length,0);
  });
});
