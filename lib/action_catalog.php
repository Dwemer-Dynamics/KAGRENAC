<?php
// The actions this server knows: when the model may ask for each one, and who it acts on.
// This file only declares a class, so requesting it over HTTP prints nothing.
// The prompt hints (actions_prompt()), the parser's target rule (extract_actions()) and
// 'project.ps1 configure' (scripts/configure_server.php) all read this one list.
// Knowing an action never allows it: only config allowed_actions does, narrowed by the game's
// offered_actions. An allowed name that is not listed here (a custom action the operator added
// on purpose) is still offered as a bare tag and returned without args, exactly as before.

final class ActionCatalog
{
    // Actions whose actor is the NPC the request named: they get it as args.target_id.
    public const TARGET_REQUEST_NPC = 'request_npc';

    // The server allowlist when config sets none.
    public const DEFAULT_ALLOWED = ['follow_player'];

    // name => ['when' => prompt hint after "Use [ACTION:name]", 'target' => target rule or null].
    // The order is the order of the hints in the prompt.
    private const KNOWN = [
        'follow_player' => ['when' => 'only when you agree to follow the player',
            'target' => self::TARGET_REQUEST_NPC],
        'hold_position' => ['when' => 'only when you agree to stay where you are',
            'target' => self::TARGET_REQUEST_NPC],
        'attack_hostile' => ['when' => 'only when you agree to attack; the game alone picks the one hostile it knows, you cannot name a target',
            'target' => self::TARGET_REQUEST_NPC],
    ];

    // Every known name, in catalog order.
    public static function names(): array
    {
        return array_keys(self::KNOWN);
    }

    // The known names whose target is the request's npc.id, in catalog order.
    public static function requestNpcTargetNames(): array
    {
        return array_keys(array_filter(self::KNOWN, fn(array $action) => $action['target'] === self::TARGET_REQUEST_NPC));
    }

    // The prompt sentences for the known actions among $tags ("[ACTION:name]" strings that the
    // prompt offers), each starting with a space, in catalog order. Unknown names get no hint.
    public static function promptHints(array $tags): string
    {
        $hints = '';
        foreach (self::KNOWN as $name => $action) {
            if (in_array("[ACTION:$name]", $tags, true)) {
                $hints .= " Use [ACTION:$name] {$action['when']}.";
            }
        }
        return $hints;
    }

    // One allowed action as the protocol returns it. The target only ever comes from the
    // request ($targetId, its npc.id), never from model text; the tag itself carries no arguments.
    public static function request(string $name, ?string $targetId): array
    {
        $action = ['name' => $name];
        if ((self::KNOWN[$name]['target'] ?? null) === self::TARGET_REQUEST_NPC && $targetId !== null) {
            $action['args'] = ['target_id' => $targetId];
        }
        return $action;
    }
}
