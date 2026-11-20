// OneSpace QA-only shared-media cleanup contract.
// Imported by the service-only purge worker. Never accepts personal buckets.
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const BUCKETS=Object.freeze({
  "onespace-note-images":new Set(["jpg","jpeg","png","webp"]),
  "onespace-memory-photos":new Set(["jpg","jpeg","png","webp"]),
  "onespace-trip-documents":new Set(["pdf","jpg","jpeg","png","webp"]),
  "onespace-activity-media":new Set(["jpg","jpeg","png","webp"]),
  "onespace-activity-voice":new Set(["m4a"]),
  "onespace-share-in":new Set(["pdf","jpg","jpeg","png","webp","heic"]),
});
export function validateMediaPurgeJob(raw){
  if(!raw||typeof raw!=="object")return null;
  const {space_id,bucket_id,object_path,lease_id,expected_uploader_id}=raw;
  if(typeof space_id!=="string"||!UUID.test(space_id)||
     typeof lease_id!=="string"||!UUID.test(lease_id)||
     typeof expected_uploader_id!=="string"||!UUID.test(expected_uploader_id)||
     typeof bucket_id!=="string"||!Object.hasOwn(BUCKETS,bucket_id)||
     typeof object_path!=="string"||object_path.length>400||
     object_path.includes("..")||object_path.includes("\\")||
     object_path.startsWith("/"))return null;
  const pathParts=object_path.split("/");
  const isInbox=bucket_id==="onespace-share-in";
  if(pathParts.length!==(isInbox?2:3))return null;
  const ownerPart=isInbox?pathParts[0]:pathParts[1];
  if(ownerPart!==expected_uploader_id)return null;
  const documentPart=pathParts.at(-1);
  const dot=documentPart.lastIndexOf(".");
  if(dot<1)return null;
  const base=documentPart.slice(0,dot);
  const extension=documentPart.slice(dot+1);
  if(!UUID.test(base)||!BUCKETS[bucket_id].has(extension))return null;
  if(!isInbox&&!UUID.test(pathParts[0]))return null;
  return {space_id,bucket_id,object_path,lease_id,expected_uploader_id};
}
