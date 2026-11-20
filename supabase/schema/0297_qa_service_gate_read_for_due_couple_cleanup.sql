-- Reconciled 2026-11-20: applied to QA (ugwrpeduzyzrujkizqfo) on 2026-11-20 from
-- qa/activities-memories-two-scope-cutover-20261120:supabase/schema/0290_qa_service_gate_read_for_due_couple_cleanup.sql (original number 0290). Kept verbatim so the
-- repository replays to the live QA schema. QA only; never apply to Production.
-- QA service may inspect the gated state when deciding whether to
-- launch a due-account relationship erase; it cannot toggle either gate.
GRANT SELECT ON private.qa_relationship_v2_gate TO service_role;
REVOKE INSERT,UPDATE,DELETE ON private.qa_relationship_v2_gate FROM service_role;
