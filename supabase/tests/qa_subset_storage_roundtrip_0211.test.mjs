import assert from "node:assert/strict";
import {test} from "node:test";
import {createHash} from "node:crypto";
import {encryptVaultSubsetFile,decryptVaultSubsetFile} from
 "../functions/_shared/qa_vault_subset_osa.mjs";
const base="https://ugwrpeduzyzrujkizqfo.supabase.co";
const owner="11111111-2222-4333-8444-555555555555";
const partner="99999999-2222-4333-8444-555555555555";
const space="88888888-2222-4333-8444-555555555555";
const stagingId="bbbbbbbb-2222-4333-8444-555555555555";
const noteId="aaaaaaaa-2222-4333-8444-555555555555";
const path=owner+"/qa-subsets/"+stagingId+".osa";
const passphrase="QA original partner protected vault passphrase";
const sha=x=>createHash("sha256").update(x).digest("hex");
const snap=JSON.stringify({
 id:noteId,space_id:space,created_by:owner,visibility:"private",
 title:"A written family memory",body:"The first time we met"
});
const row={
 kind:"root",source_table:"notes",source_id:noteId,parent_table:null,parent_id:null,
 snapshot_json:snap,snapshot_bytes:new TextEncoder().encode(snap).length,
 snapshot_sha256:sha(snap)
};
const manifest={
 schema:"onespace.qa.private-vault-subset-manifest.v1",
 owner_id:owner,source_space_id:space,
 root_types_in_scope:14,dependent_types_in_scope:9,
 record_count:1,root_record_count:1,child_record_count:0,
 snapshot_plaintext_bytes:row.snapshot_bytes,
 subset_sha256:sha("onespace.qa.private.vault-subset.v1|"+owner+"|"+space+
  "|root|notes|"+noteId+"|"+row.snapshot_sha256),
 records:[row],media_included:false,documents_included:false,
 all_69_types_packaged:false,source_manifest_scope_complete:true,
 archive_issued:false,server_signed:false,is_verified_archive:false,
 can_restore:false,safe_to_archive:false,safe_to_separate:false
};
const env={
 SUPABASE_URL:base,SUPABASE_ANON_KEY:"test-publishable-key",
 SUPABASE_SERVICE_ROLE_KEY:"test-service-role-key"
};
let handler;
globalThis.Deno={env:{get:k=>env[k]},serve:fn=>{handler=fn}};
await import("../functions/onespace-qa-subset-file/index.ts");
assert.equal(typeof handler,"function");
const url=(action,params={})=>{
 const u=new URL(base+"/functions/v1/onespace-qa-subset-file");
 u.searchParams.set("action",action);
 for(const [key,value] of Object.entries(params))u.searchParams.set(key,value);
 return u.toString();
};
const upload=(bytes,bearer="Bearer alice")=>new Request(url("upload",{source_space_id:space}),{
 method:"POST",headers:{"authorization":bearer,"content-type":"application/octet-stream"},
 body:bytes
});
const download=(id=stagingId,bearer="Bearer alice")=>new Request(url("download",{staging_id:id}),{
 method:"POST",headers:bearer?{authorization:bearer}:{}
});
function mocks(opts={}){
 const calls=[],objects=new Map();
 let available=null,failed=false,deleted=false;
 globalThis.fetch=async(input,options={})=>{
  const href=String(input),method=options.method??"GET";
  calls.push({href,method,body:options.body,headers:options.headers});
  if(href.endsWith("/auth/v1/user")){
   if(opts.authDenied)return Response.json({error:"expired"},{status:401});
   return Response.json({id:options.headers.authorization==="Bearer bob"?partner:owner});
  }
  if(href.endsWith("/rest/v1/rpc/qa_subset_reserve_service")){
   const args=JSON.parse(options.body);
   assert.equal(args.p_owner,owner);
   assert.equal(args.p_space,space);
   return Response.json({staging_id:stagingId,object_path:path,
    is_verified_archive:false,can_restore:false});
  }
  if(href.endsWith("/rest/v1/rpc/qa_subset_mark_available_service")){
   const args=JSON.parse(options.body);
   assert.equal(args.p_id,stagingId);
   const stored=objects.get(path);
   assert.equal(args.p_sha256,sha(stored));
   assert.equal(args.p_byte_length,stored.length);
   available={staging_id:stagingId,owner_id:owner,source_space_id:space,
    object_path:path,ciphertext_sha256:args.p_sha256,
    byte_length:args.p_byte_length,
    is_verified_archive:false,can_restore:false};
   return Response.json(true);
  }
  if(href.endsWith("/rest/v1/rpc/qa_subset_mark_failed_service")){
   failed=true;return Response.json(true);
  }
  if(href.endsWith("/rest/v1/rpc/qa_subset_lookup_service")){
   const args=JSON.parse(options.body);
   return Response.json(args.p_owner===owner&&args.p_id===stagingId?available:null);
  }
  if(href.includes("/storage/v1/object/authenticated/onespace-archives/")){
   const key=decodeURIComponent(href.split("/onespace-archives/")[1]);
   const original=objects.get(key);
   if(!original)return Response.json({error:"missing"},{status:404});
   const data=new Uint8Array(original);
   if(opts.tamperRead)data[11]^=13;
   if(opts.truncateRead)return new Response(data.slice(0,-1));
   return new Response(data,{headers:{"content-length":String(data.length)}});
  }
  if(href.includes("/storage/v1/object/onespace-archives/")&&method==="POST"){
   const key=decodeURIComponent(href.split("/onespace-archives/")[1]);
   objects.set(key,new Uint8Array(options.body));
   return Response.json({Key:key});
  }
  if(href.endsWith("/storage/v1/object/onespace-archives")&&method==="DELETE"){
   for(const k of JSON.parse(options.body).prefixes)objects.delete(k);
   deleted=true;return Response.json([]);
  }
  throw new Error("Unmocked QA backend: "+method+" "+href);
 };
 return {calls,objects,get available(){return available},
  get failed(){return failed},get deleted(){return deleted}};
}
test("QA subset Storage bytes: authenticated owner upload, readback SHA, private download and independent AES decryption",async()=>{
 const file=await encryptVaultSubsetFile(manifest,passphrase);
 const mock=mocks();
 const issue=await handler(upload(file));
 assert.equal(issue.status,200);
 const response=await issue.json();
 assert.equal(response.staging_id,stagingId);
 assert.equal(response.verified_storage_bytes,true);
 assert.equal(response.is_verified_archive,false);
 assert.equal(response.can_restore,false);
 assert.equal(response.safe_to_separate,false);
 assert.equal(response.encrypted_sha256,sha(file));
 assert.equal(mock.available.byte_length,file.length);
 assert.equal(mock.objects.get(path).length,file.length);
 const delivered=await handler(download());
 assert.equal(delivered.status,200);
 assert.equal(delivered.headers.get("x-onespace-unverified-subset"),"true");
 const bytes=new Uint8Array(await delivered.arrayBuffer());
 assert.equal(sha(bytes),sha(file));
 const restored=await decryptVaultSubsetFile(bytes,passphrase,owner,space);
 assert.equal(restored.manifest.records.length,1);
 assert.equal(restored.verified_record_snapshots,true);
 assert.equal(restored.verified_source_origin,false);
 assert.equal(restored.can_restore,false);
});
test("partner cannot download owner's staged file after their valid sign-in",async()=>{
 const mock=mocks();
 await handler(upload(await encryptVaultSubsetFile(manifest,passphrase)));
 const res=await handler(download(stagingId,"Bearer bob"));
 assert.equal(res.status,404);
 assert.equal(mock.calls.filter(x=>x.href.includes("/object/authenticated")).length,1);
});
test("same-size Storage tamper during issuance fails before marking available and removes staged object",async()=>{
 const mock=mocks({tamperRead:true});
 const result=await handler(upload(await encryptVaultSubsetFile(manifest,passphrase)));
 assert.equal(result.status,409);
 assert.equal(mock.failed,true);
 assert.equal(mock.deleted,true);
 assert.equal(mock.available,null);
 assert.equal(mock.objects.size,0);
});
test("tampering an already available private object prevents download despite matching byte size",async()=>{
 const mock=mocks();
 await handler(upload(await encryptVaultSubsetFile(manifest,passphrase)));
 const stored=mock.objects.get(path);
 stored[14]^=17;
 const result=await handler(download());
 assert.equal(result.status,409);
});
test("invalid users, production environment and malformed .osa files fail before any Storage write",async()=>{
 const file=await encryptVaultSubsetFile(manifest,passphrase);
 const mock=mocks();
 assert.equal((await handler(download(stagingId,""))).status,401);
 assert.equal((await handler(download("not-an-id"))).status,400);
 const invalid=new Uint8Array(file);
 invalid[0]^=12;
 const denied=await handler(upload(invalid));
 assert.equal(denied.status,409);
 assert.equal(mock.objects.size,0);
 const old=env.SUPABASE_URL;
 env.SUPABASE_URL="https://letcgxbnblohhfyeuigz.supabase.co";
 try{assert.equal((await handler(upload(file))).status,503)}
 finally{env.SUPABASE_URL=old;}
});
