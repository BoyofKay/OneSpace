# Coordinate — Workspace overview and discovery

## Sections
- **Active:** everything currently being explored, compared, purchased, etc. Does not include cancelled, completed, or archived Activities.
- **Attention:** active, unarchived Activities that are marked high/urgent priority or have a due date within seven calendar days, including overdue.
- **Finished:** completed or cancelled Activities. Completed research remains accessible, without erasing options or conversation.
- **All:** includes archived records for historic access.
- A case-insensitive search matches the Activity title or body without making a new database query on every keystroke.
- The main list remains live via Supabase Realtime and respects existing Activity RLS.

## Creation
- Minimal title/body with optional private toggle. Priority, due date, and other components can be added later.
- A connected couple sees no legacy project-management requirement to assign a Task or choose a deadline.

## Outcomes
- Registration is a terminal successful outcome, so it now sets the Activity stage to `completed`. The Decision event remains `registered` for display and historical clarity.
- Purchase remains in progress until delivery; delivery completes the Activity.
- Reopening creates a new Decision event without erasing earlier history.

## Acceptance
- Create three Activities, complete one, archive one, mark one as urgent; counts and filters must agree.
- An overdue Activity appears in Attention. An Activity due more than seven days later does not, unless high/urgent.
- All lists show only Activities returned by RLS.
- A registered gymnastics enrollment goes to Finished and stays fully searchable.
- Toggling between views and searching must not create extra round-trips or duplicate realtime subscriptions.
