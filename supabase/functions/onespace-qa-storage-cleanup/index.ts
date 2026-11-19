// QA one-time orphan cleanup completed on 2026-11-19.
// The endpoint is permanently retired to prevent accidental repeat executions.
// No service-role key or worker secret is read.
Deno.serve((_req)=>new Response(
  JSON.stringify({error:"QA one-time cleanup completed; endpoint retired"}),
  {status:410,headers:{"content-type":"application/json","cache-control":"no-store"}}
));