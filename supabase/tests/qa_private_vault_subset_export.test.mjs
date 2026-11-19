import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {test} from "node:test";
import {mkdtemp,readFile,rm,stat} from "node:fs/promises";
import {join} from "node:path";
import {tmpdir} from "node:os";
import {exportQaPrivateVaultSubset,verifyLocalQaSubsetFile}
 from "../scripts/qa_private_vault_subset_export.mjs";

const owner="11111111-2222-4333-8444-555555555555";
const space="99999999-2222-4333-8444-555555555555";
const id="aaaaaaaa-2222-4333-8444-555555555555";
const passphrase="A genuinely long recovery secret for QA local export";
const host="https://ugwrpeduzyzrujkizqfo.supabase.co";
const anonKey="QA_PUBLISHABLE_TEST_KEY_1234567";
const accessToken="qa.mock.authenticated.jwt.for.testing";
const sha=x=>createHash("sha256").update(x).digest("hex");
function fixture(){
 const source=JSON.stringify({id,space_id:space,created_by:owner,visibility:"private",
  title:"Owner-only written trip planning",body:"Keep this personal story"});
 const snapHash=sha(source);
 const entry={kind:"root",source_table:"notes",source_id:id,
  parent_table:null,parent_id:null,snapshot_json:source,
  snapshot_sha256:snapHash,snapshot_bytes:new TextEncoder().encode(source).length};
 return {schema:"onespace.qa.private-vault-subset-manifest.v1",
  owner_id:owner,source_space_id:space,
  root_types_in_scope:14,dependent_types_in_scope:9,
  record_count:1,root_record_count:1,child_record_count:0,
  snapshot_plaintext_bytes:entry.snapshot_bytes,
  subset_sha256:sha("onespace.qa.private.vault-subset.v1|"+owner+"|"+space+
   "|root|notes|"+id+"|"+snapHash),
  records:[entry],media_included:false,documents_included:false,
  all_69_types_packaged:false,source_manifest_scope_complete:true,
  archive_issued:false,server_signed:false,
  is_verified_archive:false,can_restore:false,
  safe_to_archive:false,safe_to_separate:false};
}
const mockFetch=(manifest=fixture())=>async(url,options)=>{
 assert.equal(url,host+"/rest/v1/rpc/qa_private_vault_subset_manifest");
 assert.equal(options.method,"POST");
 assert.equal(options.headers.apikey,anonKey);
 assert.equal(options.headers.Authorization,"Bearer "+accessToken);
 assert.equal(options.body,"{}");
 assert.ok(!JSON.stringify(options).includes(passphrase));
 return new Response(JSON.stringify(manifest),{
   status:200,headers:{"Content-Type":"application/json"}
 });
};
async function withFolder(callback){
 const folder=await mkdtemp(join(tmpdir(),"onespace-qa-osa-export-"));
 try{return await callback(join(folder,"private-subset.osa"))}
 finally{await rm(folder,{recursive:true,force:true})}
}
test("authenticated QA RPC writes genuine .osa bytes and independently decrypts saved file",async()=>{
 await withFolder(async destination=>{
  const result=await exportQaPrivateVaultSubset({
    url:host,anonKey,accessToken,passphrase,destination,
    fetchImpl:mockFetch()
  });
  assert.equal(result.destination,destination);
  assert.equal(result.source_record_count,1);
  assert.equal(result.is_complete_onespace_archive,false);
  assert.equal(result.can_restore,false);
  const content=new Uint8Array(await readFile(destination));
  assert.equal(sha(content),result.encrypted_sha256);
  assert.ok(content.length>100);
  const metadata=await stat(destination);
  assert.equal(metadata.mode&0o777,0o600);
  const restored=await verifyLocalQaSubsetFile({
    archiveBytes:content,passphrase,ownerId:owner,spaceId:space
  });
  assert.equal(restored.verified_record_snapshots,true);
  assert.equal(restored.verified_source_origin,false);
  assert.equal(restored.can_restore,false);
  assert.equal(restored.manifest.records[0].snapshot_sha256,fixture().records[0].snapshot_sha256);
 });
});
test("Production Supabase and arbitrary hosts are forbidden even with valid account JWT",async()=>{
 await withFolder(async destination=>{
  const inputs=[
    "https://letcgxbnblohhfyeuigz.supabase.co",
    "http://ugwrpeduzyzrujkizqfo.supabase.co",
    "https://ugwrpeduzyzrujkizqfo.supabase.co.evil.com",
    "https://admin@ugwrpeduzyzrujkizqfo.supabase.co",
    "https://ugwrpeduzyzrujkizqfo.supabase.co/unsafe",
  ];
  for(const url of inputs){
   await assert.rejects(
    exportQaPrivateVaultSubset({url,anonKey,accessToken,passphrase,destination,
      fetchImpl:()=>{throw Error("unexpected network call")}}),
    /QA archive RPC export rejected/);
  }
 });
});
test("failed authentication and oversized response cannot generate a file",async()=>{
 await withFolder(async destination=>{
  const one=()=>Promise.resolve(new Response("Unauthorized",{status:401}));
  await assert.rejects(exportQaPrivateVaultSubset({
   url:host,anonKey,accessToken,passphrase,destination,fetchImpl:one
  }));
  const huge=()=>Promise.resolve(new Response("{}",{
   status:200,headers:{"Content-Length":String(20*1024*1024)}
  }));
  await assert.rejects(exportQaPrivateVaultSubset({
   url:host,anonKey,accessToken,passphrase,destination,fetchImpl:huge
  }));
  await assert.rejects(readFile(destination),{code:"ENOENT"});
 });
});
test("source that fails ownership/media checks is never written",async()=>{
 await withFolder(async destination=>{
  const changed=fixture();
  changed.owner_id="22222222-2222-4333-8444-555555555555";
  await assert.rejects(exportQaPrivateVaultSubset({
    url:host,anonKey,accessToken,passphrase,destination,fetchImpl:mockFetch(changed)
  }));
  await assert.rejects(readFile(destination),{code:"ENOENT"});
 });
});
test("cannot overwrite an existing ciphertext archive file",async()=>{
 await withFolder(async destination=>{
  const args={url:host,anonKey,accessToken,passphrase,destination,
   fetchImpl:mockFetch()};
  await exportQaPrivateVaultSubset(args);
  const old=await readFile(destination);
  await assert.rejects(exportQaPrivateVaultSubset(args),{code:"EEXIST"});
  const next=await readFile(destination);
  assert.deepEqual(old,next);
 });
});
