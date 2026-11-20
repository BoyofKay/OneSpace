import test from "node:test";
import assert from "node:assert/strict";
import {validateMediaPurgeJob} from "./qa_shared_media_purge_contract.mjs";

const pair="a1111111-1111-4111-8111-111111111111";
const owner="b2222222-2222-4222-8222-222222222222";
const root="c3333333-3333-4333-8333-333333333333";
const file="d4444444-4444-4444-8444-444444444444";
const lease="e5555555-5555-4555-8555-555555555555";
const valid=(bucket_id,ext,shareIn=false)=>({
 space_id:pair,bucket_id,lease_id:lease,expected_uploader_id:owner,
 object_path:shareIn?`${owner}/${file}.${ext}`:`${root}/${owner}/${file}.${ext}`,
});

test("Every approved relationship bucket accepts only its supported extension",()=>{
 for(const [bucket,ext,isInbox] of [
  ["onespace-note-images","jpg",false],
  ["onespace-memory-photos","webp",false],
  ["onespace-trip-documents","pdf",false],
  ["onespace-activity-media","png",false],
  ["onespace-activity-voice","m4a",false],
  ["onespace-share-in","heic",true],
 ]){
  const source=valid(bucket,ext,isInbox);
  assert.deepEqual(validateMediaPurgeJob(source),source);
 }
});

test("OneSpace personal buckets and unrelated buckets cannot be purged",()=>{
 for(const bucket of [
  "onespace-private-note-images","onespace-private-memory-photos",
  "onespace-private-trip-documents","onespace-archives","onespace-support",
 ]){
  assert.equal(validateMediaPurgeJob(valid(bucket,"jpg")),null);
 }
});

test("Rejects forged authors, path escapes, wrong root and extension",()=>{
 const item=valid("onespace-note-images","jpg");
 for(const changed of [
  {...item,object_path:`${root}/${pair}/${file}.jpg`},
  {...item,expected_uploader_id:pair},
  {...item,object_path:`${root}/${owner}/../${file}.jpg`},
  {...item,object_path:`/${root}/${owner}/${file}.jpg`},
  {...item,object_path:`${root}\\${owner}\\${file}.jpg`},
  {...item,object_path:`${root}/${owner}/${file}.pdf`},
  {...item,object_path:`${root}/${owner}/${file}.JPG`},
  {...item,object_path:`${owner}/${file}.jpg`},
  {...item,object_path:`not-a-root/${owner}/${file}.jpg`},
  {...item,space_id:"not-a-space"},
  {...item,lease_id:"bad-token"},
  {...item,object_path:"x".repeat(401)},
  {},
  null,
 ]){
  assert.equal(validateMediaPurgeJob(changed),null);
 }
});
test("Share-in uses author as the first path segment",()=>{
 const ok=valid("onespace-share-in","pdf",true);
 assert.deepEqual(validateMediaPurgeJob(ok),ok);
 assert.equal(validateMediaPurgeJob({...ok,object_path:`${pair}/${file}.pdf`}),null);
});
