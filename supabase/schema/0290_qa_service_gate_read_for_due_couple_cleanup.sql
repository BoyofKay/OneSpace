-- QA service may inspect the gated state when deciding whether to
-- launch a due-account relationship erase; it cannot toggle either gate.
GRANT SELECT ON private.qa_relationship_v2_gate TO service_role;
REVOKE INSERT,UPDATE,DELETE ON private.qa_relationship_v2_gate FROM service_role;
