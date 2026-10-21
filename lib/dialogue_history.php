<?php
// The saved dialogue lines (ex_turns) of one session and NPC: reading the newest lines and
// saving one exchange. This file only declares a class, so requesting it over HTTP prints nothing.
// It owns the SQL only. Transactions, the session lock and the generation check stay with the
// caller (run_turn() in lib/turn.php), so the lock order stays visible in one place.

require_once __DIR__ . '/app.php';

final class DialogueHistory
{
    public function __construct(private \PgSql\Connection $db)
    {
    }

    // The newest $limit lines, oldest first, as rows of role and text. A query error answers
    // 500 through db_query(), for request code that has not replied yet.
    public function recent(string $sessionId, string $npcId, int $limit): array
    {
        return pg_fetch_all(db_query($this->db, $this->recentSql(), [$sessionId, $npcId, $limit]));
    }

    // Like recent(), but returns null (error logged) instead of answering, for work that runs
    // after the reply was sent.
    public function tryRecent(string $sessionId, string $npcId, int $limit): ?array
    {
        $result = db_try($this->db, $this->recentSql(), [$sessionId, $npcId, $limit]);
        return $result === null ? null : pg_fetch_all($result);
    }

    // Saves the player's line and the NPC's reply, then keeps only the newest $keep lines.
    // Call it inside the caller's transaction, after the session lock and generation check.
    public function appendExchange(string $sessionId, string $npcId, string $playerText, string $reply, int $keep): void
    {
        db_query($this->db,
            "INSERT INTO ex_turns (session_id, npc_id, role, text) VALUES ($1, $2, 'player', $3), ($1, $2, 'npc', $4)",
            [$sessionId, $npcId, $playerText, $reply]);
        db_query($this->db,
            'DELETE FROM ex_turns WHERE session_id = $1 AND npc_id = $2 AND id NOT IN (
                SELECT id FROM ex_turns WHERE session_id = $1 AND npc_id = $2 ORDER BY id DESC LIMIT $3
             )',
            [$sessionId, $npcId, $keep]);
    }

    private function recentSql(): string
    {
        return 'SELECT role, text FROM (
            SELECT id, role, text FROM ex_turns WHERE session_id = $1 AND npc_id = $2 ORDER BY id DESC LIMIT $3
         ) recent ORDER BY id';
    }
}
