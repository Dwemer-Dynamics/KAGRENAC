// KAGRENAC erpack: original, bounded tool for the Elden Ring control package.
// Uses only the public SoulsFormats API from the user's own WitchyBND 3.0.1 release.
//   inspect  lists MSB enemies with their think/NPC param rows, LUAINFO entries, NPC teams,
//            think rows and action buttons
//   pack     adds one compiled Lua logic (+ LUAINFO/LUAGNL names) to a copy of aicommon.luabnd
//            and clones one NpcThinkParam row in a copy of regulation.bin, then re-reads both
//   merge-events  adds one owned event and its InitializeEvent from a compiled common.emevd to
//            the game's original one, so no game event is re-encoded by the script compiler;
//            --check-events: map event files the id must also be free in; --expect-teams and
//            --expect-entity: what every SetCharacterTeamType must set and target
// It reads its inputs and writes only new files (the spec's out_dir, or --out), never overwriting:
// outputs go to *.partial and are moved into place only after re-read verification passes.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using SoulsFormats.Cryptography;
using System.Text.Json;
using SoulsFormats;

static class Program
{
    static int Main(string[] args)
    {
        try
        {
            var opt = Parse(args);
            if (opt.TryGetValue("oodle", out var oodle)) System.Runtime.InteropServices.NativeLibrary.Load(oodle[0]);
            return args[0] switch
            {
                "inspect" => Inspect(opt),
                "pack" => Pack(opt),
                "merge-events" => MergeEvents(opt),
                _ => Fail("usage: erpack inspect|pack|merge-events --option value ..."),
            };
        }
        catch (Exception e) { return Fail(e.ToString()); }
    }

    static int Fail(string why) { Console.Error.WriteLine("erpack: " + why); return 1; }

    // Padding and array cells hold byte arrays; compare them by content.
    static bool Same(object a, object b) =>
        a is byte[] x && b is byte[] y ? x.AsSpan().SequenceEqual(y) : Equals(a, b);

    // Compression is a settings object; compare its type and public values, not the reference.
    static string Dcx(object c) => c.GetType().Name + JsonSerializer.Serialize(c, c.GetType());

    static Dictionary<string, List<string>> Parse(string[] args)
    {
        var d = new Dictionary<string, List<string>>();
        string key = null;
        foreach (var a in args.Skip(1))
        {
            if (a.StartsWith("--")) { key = a[2..]; d[key] = new List<string>(); }
            else if (key != null) d[key].Add(a);
            else throw new ArgumentException("unexpected " + a);
        }
        return d;
    }

    static string One(Dictionary<string, List<string>> o, string k) =>
        o.TryGetValue(k, out var v) && v.Count == 1 ? v[0] : throw new ArgumentException("need --" + k);

    static PARAM LoadParam(BND4 reg, string defsDir, string name)
    {
        var file = reg.Files.Single(f => Path.GetFileName(f.Name) == name + ".param");
        var p = PARAM.Read(file.Bytes);
        p.ApplyParamdef(PARAMDEF.XmlDeserialize(Path.Combine(defsDir, name + ".xml")));
        return p;
    }

    static int Inspect(Dictionary<string, List<string>> o)
    {
        var reg = RegulationDecryptor.DecryptERRegulation(One(o, "regulation"));
        var defs = One(o, "paramdex");
        var think = LoadParam(reg, defs, "NpcThinkParam");
        var npc = LoadParam(reg, defs, "NpcParam");
        Console.WriteLine($"regulation version={reg.Version} compression={reg.Compression}");
        foreach (var path in o.GetValueOrDefault("msb") ?? new List<string>())
        {
            var msb = MSBE.Read(path);
            Console.WriteLine($"== {Path.GetFileName(path)} enemies={msb.Parts.Enemies.Count}");
            foreach (var e in msb.Parts.Enemies)
            {
                var t = think.Rows.FirstOrDefault(r => r.ID == e.ThinkParamID);
                var n = npc.Rows.FirstOrDefault(r => r.ID == e.NPCParamID);
                Console.WriteLine($"{e.Name} model={e.ModelName} entity={e.EntityID} npc={e.NPCParamID} think={e.ThinkParamID} " +
                    $"talk={e.TalkID} groups={string.Join("/", e.EntityGroupIDs.Where(g => g != 0))} " +
                    $"logic={t?["logicId"].Value} goal={t?["battleGoalID"].Value} team={n?["teamType"].Value} npcType={n?["npcType"].Value}");
            }
        }
        if (o.TryGetValue("luabnd", out var lb))
        {
            var bnd = BND4.Read(lb[0]);
            var info = LUAINFO.Read(bnd.Files.Single(f => f.Name.EndsWith(".luainfo")).Bytes);
            foreach (var g in info.Goals.Where(g => g.BattleInterrupt || g.Name.EndsWith("_Battle")).Take(6))
                Console.WriteLine($"goal {g.ID} {g.Name} battle={g.BattleInterrupt} logic={g.LogicInterrupt} '{g.LogicInterruptName}'");
            Console.WriteLine($"luabnd files={bnd.Files.Count} maxId={bnd.Files.Where(f => f.ID < 1000000).Max(f => f.ID)} goals={info.Goals.Count}");
        }
        foreach (var id in (o.GetValueOrDefault("npc") ?? new List<string>()).Select(int.Parse))
            Console.WriteLine($"npc {id} team={npc.Rows.FirstOrDefault(r => r.ID == id)?["teamType"].Value}");
        foreach (var id in (o.GetValueOrDefault("think") ?? new List<string>()).Select(int.Parse))
            Console.WriteLine($"think {id} exists={think.Rows.Any(r => r.ID == id)}");
        if (o.TryGetValue("buttons", out var ids))
        {
            var ab = LoadParam(reg, defs, "ActionButtonParam");
            foreach (var id in ids.Select(int.Parse))
            {
                var r = ab.Rows.FirstOrDefault(x => x.ID == id);
                Console.WriteLine(r == null ? $"button {id} missing" : $"button {id} " + string.Join(" ",
                    new[] { "regionType", "category", "radius", "height", "angle", "textId", "dummyPoly1" }.Select(c => $"{c}={r[c].Value}")));
            }
        }
        return 0;
    }

    sealed class Spec
    {
        public string luabnd { get; set; }
        public string lua_bytecode { get; set; }
        public string lua_file { get; set; }
        public int logic_id { get; set; }
        public string logic_name { get; set; }
        public string[] globals { get; set; }
        public string regulation { get; set; }
        public string paramdex { get; set; }
        public int think_source { get; set; }
        public int think_new { get; set; }
        public string out_dir { get; set; }
    }

    static int Pack(Dictionary<string, List<string>> o)
    {
        var s = JsonSerializer.Deserialize<Spec>(File.ReadAllText(One(o, "spec")));
        // Never overwrite: refuse before any write if a final or partial output is already there.
        var luaOut = Path.Combine(s.out_dir, "script", "aicommon.luabnd.dcx");
        var regOut = Path.Combine(s.out_dir, "regulation.bin");
        foreach (var p in new[] { luaOut, regOut, luaOut + ".partial", regOut + ".partial" }.Where(Path.Exists))
            return Fail("output already exists, refusing to overwrite: " + p);
        var code = File.ReadAllBytes(s.lua_bytecode);
        var luaHeader = new byte[] { 0x1b, 0x4c, 0x75, 0x61, 0x50, 0x01, 0x04, 0x08, 0x04, 0x06, 0x08, 0x09, 0x09, 0x08 };
        if (!code.Take(luaHeader.Length).SequenceEqual(luaHeader)) return Fail("bytecode is not Lua 5.0 x64 (header differs)");

        // aicommon.luabnd: one new entry in the game's own folder, with the same header as the
        // game's entries, plus the logic in LUAINFO (as the game lists its logics) and its globals in LUAGNL.
        var bnd = BND4.Read(s.luabnd);
        var game = bnd.Files.Where(f => f.Name.EndsWith(".lua")).ToList();
        if (!game.All(f => f.Bytes.Take(luaHeader.Length).SequenceEqual(luaHeader))) return Fail("game Lua entries have another header");
        var dir = game[0].Name[..(game[0].Name.LastIndexOf('\\') + 1)];
        if (bnd.Files.Any(f => Path.GetFileName(f.Name).Equals(s.lua_file, StringComparison.OrdinalIgnoreCase))) return Fail(s.lua_file + " already in luabnd");
        var infoFile = bnd.Files.Single(f => f.Name.EndsWith(".luainfo"));
        var gnlFile = bnd.Files.Single(f => f.Name.EndsWith(".luagnl"));
        var info = LUAINFO.Read(infoFile.Bytes);
        var gnl = LUAGNL.Read(gnlFile.Bytes);
        if (info.Goals.Any(g => g.ID == s.logic_id)) return Fail("logic id already registered in LUAINFO");
        if (s.globals.Any(gnl.Globals.Contains)) return Fail("a global name is already in LUAGNL");
        // The game registers every logic as <name><id>_Logic, no battle interrupt, logic interrupt
        // <name><id>_Interupt (the game's spelling). Check that on the input, then mirror it.
        var logics = info.Goals.Where(g => g.LogicInterrupt).ToList();
        bool LogicShape(LUAINFO.Goal g) => !g.BattleInterrupt && g.LogicInterrupt && g.Name.EndsWith("_Logic")
            && g.Name[..^6].EndsWith(g.ID.ToString()) && g.LogicInterruptName == g.Name[..^6] + "_Interupt";
        if (logics.Count == 0 || !logics.All(LogicShape)) return Fail("LUAINFO logic entries do not follow the expected naming; not guessing");
        var newGoal = new LUAINFO.Goal(s.logic_id, s.logic_name + "_Logic", false, true, s.logic_name + "_Interupt");
        if (!LogicShape(newGoal)) return Fail($"logic_name must end with the logic id {s.logic_id}, as the game's logics do");
        if (info.Goals.Any(g => g.Name == newGoal.Name || g.LogicInterruptName == newGoal.LogicInterruptName)) return Fail("logic name already in LUAINFO");
        // Keep the table's order: sorted by id gets a sorted insert, otherwise the entry goes last.
        bool infoSorted = info.Goals.Zip(info.Goals.Skip(1)).All(p => p.First.ID < p.Second.ID);
        int goalAt = infoSorted ? info.Goals.Count(g => g.ID < s.logic_id) : info.Goals.Count;
        var id = game.Max(f => f.ID) + 1;
        if (bnd.Files.Any(f => f.ID == id)) return Fail($"entry id {id} taken");
        // Same for the files: the originals keep their order, the new one goes in by id or last.
        bool bndSorted = bnd.Files.Zip(bnd.Files.Skip(1)).All(p => p.First.ID < p.Second.ID);
        int fileAt = bndSorted ? bnd.Files.Count(f => f.ID < id) : bnd.Files.Count;
        bnd.Files.Insert(fileAt, new BinderFile(game[0].Flags, id, dir + s.lua_file, code));
        info.Goals.Insert(goalAt, newGoal);
        gnl.Globals.AddRange(s.globals);
        infoFile.Bytes = info.Write();
        gnlFile.Bytes = gnl.Write();
        Directory.CreateDirectory(Path.GetDirectoryName(luaOut));
        bnd.Write(luaOut + ".partial", bnd.Compression);

        // regulation.bin copy: clone the companion's think row; only logicId changes. battleGoalID
        // is kept for compatibility; the control logic does not queue it.
        var reg = RegulationDecryptor.DecryptERRegulation(s.regulation);
        var thinkFile = reg.Files.Single(f => Path.GetFileName(f.Name) == "NpcThinkParam.param");
        var think = PARAM.Read(thinkFile.Bytes);
        think.ApplyParamdef(PARAMDEF.XmlDeserialize(Path.Combine(s.paramdex, "NpcThinkParam.xml")));
        var src = think.Rows.SingleOrDefault(r => r.ID == s.think_source);
        if (src == null) return Fail($"NpcThinkParam {s.think_source} not found");
        if (think.Rows.Any(r => r.ID == s.think_new)) return Fail($"NpcThinkParam {s.think_new} already exists");
        var row = new PARAM.Row(s.think_new, "KAGRENAC companion control", think.AppliedParamdef);
        for (int i = 0; i < src.Cells.Count; i++)
            row.Cells[i].Value = src.Cells[i].Value is byte[] b ? b.Clone() : src.Cells[i].Value;
        row["logicId"].Value = s.logic_id;
        think.Rows.Add(row);
        think.Rows.Sort((a, b) => a.ID.CompareTo(b.ID));
        thinkFile.Bytes = think.Write();
        RegulationDecryptor.EncryptERRegulation(regOut + ".partial", reg);

        // Re-read what was written and compare it with fresh reads of the inputs.
        var bnd0 = BND4.Read(s.luabnd);
        var info0 = LUAINFO.Read(bnd0.Files.Single(f => f.Name.EndsWith(".luainfo")).Bytes);
        var gnl0 = LUAGNL.Read(bnd0.Files.Single(f => f.Name.EndsWith(".luagnl")).Bytes);
        var bnd2 = BND4.Read(luaOut + ".partial");
        var entry = bnd2.Files.Single(f => f.ID == id);
        var info2 = LUAINFO.Read(bnd2.Files.Single(f => f.Name.EndsWith(".luainfo")).Bytes);
        var gnl2 = LUAGNL.Read(bnd2.Files.Single(f => f.Name.EndsWith(".luagnl")).Bytes);
        var reg0 = RegulationDecryptor.DecryptERRegulation(s.regulation);
        var reg2 = RegulationDecryptor.DecryptERRegulation(regOut + ".partial");
        PARAM ReadThink(BND4 r)
        {
            var t = PARAM.Read(r.Files.Single(f => Path.GetFileName(f.Name) == "NpcThinkParam.param").Bytes);
            t.ApplyParamdef(think.AppliedParamdef);
            return t;
        }
        var think0 = ReadThink(reg0);
        var think2 = ReadThink(reg2);
        var r2 = think2.Rows.Single(r => r.ID == s.think_new);
        var s2 = think2.Rows.Single(r => r.ID == s.think_source);
        var differing = Enumerable.Range(0, r2.Cells.Count).Where(i => !Same(r2.Cells[i].Value, s2.Cells[i].Value)).ToList();

        // Collateral: everything else must equal a fresh read of the inputs.
        bool SameFile(BinderFile a, BinderFile b, bool bytes) =>
            a.ID == b.ID && a.Name == b.Name && a.Flags == b.Flags && (!bytes || a.Bytes.AsSpan().SequenceEqual(b.Bytes));
        var regBad = reg2.Files.Count != reg0.Files.Count ? new List<string> { "file count" } : Enumerable.Range(0, reg0.Files.Count)
            .Where(i => !SameFile(reg0.Files[i], reg2.Files[i], Path.GetFileName(reg0.Files[i].Name) != "NpcThinkParam.param"))
            .Select(i => reg0.Files[i].Name).ToList();
        var rows2 = think2.Rows.Where(r => r.ID != s.think_new).ToList();
        var rowsBad = rows2.Count != think0.Rows.Count ? new List<int> { -1 } : Enumerable.Range(0, rows2.Count)
            .Where(i => rows2[i].ID != think0.Rows[i].ID || rows2[i].Name != think0.Rows[i].Name
                || Enumerable.Range(0, rows2[i].Cells.Count).Any(c => !Same(rows2[i].Cells[c].Value, think0.Rows[i].Cells[c].Value)))
            .Select(i => think0.Rows[i].ID).ToList();
        bool Meta(BinderFile f) => f.Name.EndsWith(".luainfo") || f.Name.EndsWith(".luagnl");
        // Position by position, with the new entry removed, so a reorder counts as a change.
        var kept = bnd2.Files.Where(f => f.ID != id).ToList();
        var luaBad = bnd2.Files.Count != bnd0.Files.Count + 1 || kept.Count != bnd0.Files.Count ? new List<string> { "file count" }
            : Enumerable.Range(0, kept.Count).Where(i => !SameFile(bnd0.Files[i], kept[i], !Meta(bnd0.Files[i])))
            .Select(i => bnd0.Files[i].Name).ToList();
        int entryAt = bnd2.Files.FindIndex(f => f.ID == id);
        bool Goal(LUAINFO.Goal a, LUAINFO.Goal b) => a.ID == b.ID && a.Name == b.Name && a.BattleInterrupt == b.BattleInterrupt
            && a.LogicInterrupt == b.LogicInterrupt && a.LogicInterruptName == b.LogicInterruptName;
        // The new entry must be exactly the one intended, at its place; the rest, with it removed,
        // must equal the original table entry for entry.
        var goalIdx = info2.Goals.FindIndex(g => g.ID == s.logic_id);
        bool goalOk = goalIdx == goalAt && info2.Goals.Count(g => g.ID == s.logic_id) == 1 && Goal(info2.Goals[goalIdx], newGoal);
        var others = info2.Goals.Where((g, i) => i != goalIdx).ToList();
        bool goalsKept = others.Count == info0.Goals.Count && info0.Goals.Select((g, i) => Goal(g, others[i])).All(x => x)
            && info2.BigEndian == info0.BigEndian && info2.LongFormat == info0.LongFormat;
        bool globalsKept = gnl2.Globals.SequenceEqual(gnl0.Globals.Concat(s.globals));
        var containerBad = new List<string>();
        if (reg2.Version != reg0.Version) containerBad.Add("regulation version");
        if (reg2.Format != reg0.Format) containerBad.Add("regulation format");
        if (Dcx(reg2.Compression) != Dcx(reg0.Compression)) containerBad.Add("regulation compression");
        if (bnd2.Version != bnd0.Version) containerBad.Add("luabnd version");
        if (bnd2.Format != bnd0.Format) containerBad.Add("luabnd format");
        if (Dcx(bnd2.Compression) != Dcx(bnd0.Compression)) containerBad.Add("luabnd compression");
        bool containers = containerBad.Count == 0;

        bool ok = entry.Bytes.SequenceEqual(code) && entry.Name == dir + s.lua_file && entry.Flags == game[0].Flags
            && entryAt == fileAt && goalOk
            && s.globals.All(gnl2.Globals.Contains) && (int)r2["logicId"].Value == s.logic_id
            && Equals(r2["battleGoalID"].Value, s2["battleGoalID"].Value)
            && differing.Select(i => r2.Cells[i].Def.InternalName).SequenceEqual(new[] { "logicId" })
            && regBad.Count == 0 && rowsBad.Count == 0 && luaBad.Count == 0 && goalsKept && globalsKept && containers;
        if (ok)
        {
            File.Move(luaOut + ".partial", luaOut, false);
            File.Move(regOut + ".partial", regOut, false);
        }
        static string Show(object v) => v is byte[] a ? Convert.ToHexString(a) : v?.ToString();
        Console.WriteLine(JsonSerializer.Serialize(new
        {
            ok, lua_entry = new { id, index = entryAt, files_sorted_by_id = bndSorted, name = entry.Name, bytes = code.Length, flags = entry.Flags.ToString() },
            luabnd_compression = Dcx(bnd2.Compression), luainfo_goals = info2.Goals.Count, luagnl_globals = gnl2.Globals.Count,
            luainfo_goal = goalIdx < 0 ? null : new { index = goalIdx, table_sorted_by_id = infoSorted, info2.Goals[goalIdx].ID, info2.Goals[goalIdx].Name,
                info2.Goals[goalIdx].BattleInterrupt, info2.Goals[goalIdx].LogicInterrupt, info2.Goals[goalIdx].LogicInterruptName, ok = goalOk },
            regulation_version = reg2.Version, regulation_compression = Dcx(reg2.Compression), think_row = s.think_new,
            think_cells_differing_from_source = differing.Select(i => r2.Cells[i].Def.InternalName),
            think_cell_diffs = differing.Select(i => new { name = r2.Cells[i].Def.InternalName, type = r2.Cells[i].Def.DisplayType.ToString(),
                value = Show(r2.Cells[i].Value), source = Show(s2.Cells[i].Value) }),
            collateral = new { regulation_files_changed = regBad, think_rows_changed = rowsBad, luabnd_files_changed = luaBad,
                luainfo_goals_kept = goalsKept, luagnl_globals_kept = globalsKept, container_metadata_changed = containerBad },
            outputs = ok ? new[] { luaOut, regOut } : new[] { luaOut + ".partial", regOut + ".partial" },
        }));
        return ok ? 0 : Fail("re-read verification failed; unverified .partial files left in place, nothing published");
    }

    static bool IsInit(EMEVD.Instruction i) => i.Bank == 2000 && (i.ID == 0 || i.ID == 6) && i.ArgData.Length >= 8;
    static uint InitTarget(EMEVD.Instruction i) => BitConverter.ToUInt32(i.ArgData, 4);
    static string Ins(EMEVD.Instruction i) => $"{i.Bank}[{i.ID}] layer={i.Layer} {Convert.ToHexString(i.ArgData)}";
    static string Par(EMEVD.Parameter p, long shift) =>
        $"{p.InstructionIndex - shift} {p.TargetStartByte} {p.SourceStartByte} {p.ByteCount} {p.UnkID}";
    // skip: leading instructions of b that a does not have (b's parameter indices shift by it).
    static bool SameEvent(EMEVD.Event a, EMEVD.Event b, int skip) =>
        a.ID == b.ID && a.RestBehavior == b.RestBehavior && a.Name == b.Name
        && a.Instructions.Select(Ins).SequenceEqual(b.Instructions.Skip(skip).Select(Ins))
        && a.Parameters.Select(p => Par(p, 0)).SequenceEqual(b.Parameters.Select(p => Par(p, skip)));

    // The script compiler re-encodes every event of the file it rebuilds. Take only the owned
    // event and its one InitializeEvent(0, id, 0) from the compiled file and add them to a fresh
    // read of the game's original file; everything else stays the original's.
    static int MergeEvents(Dictionary<string, List<string>> o)
    {
        string origPath = One(o, "original"), compPath = One(o, "compiled"), outPath = One(o, "out");
        var id = uint.Parse(One(o, "event"));
        var expectTeams = (o.GetValueOrDefault("expect-teams") ?? new List<string>()).Select(byte.Parse).ToList();
        uint? expectEntity = o.ContainsKey("expect-entity") ? uint.Parse(One(o, "expect-entity")) : null;
        foreach (var p in new[] { outPath, outPath + ".partial" }.Where(Path.Exists))
            return Fail("output already exists, refusing to overwrite: " + p);
        var full = Path.GetFullPath(outPath);
        if (new[] { origPath, compPath }.Any(p => Path.GetFullPath(p).Equals(full, StringComparison.OrdinalIgnoreCase)))
            return Fail("--out must be a new path, not an input");
        var origHash = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(origPath)));

        var orig = EMEVD.Read(origPath);
        var comp = EMEVD.Read(compPath);
        bool Uses(EMEVD f) => f.Events.Any(e => e.ID == id || e.Instructions.Any(i => IsInit(i) && InitTarget(i) == id));
        if (Uses(orig)) return Fail($"event {id} already exists in, or is started by, the original file");
        // The id must also be free in the given original map event files (ids and starts only).
        var idChecks = new List<object>();
        foreach (var path in o.GetValueOrDefault("check-events") ?? new List<string>())
        {
            var m = EMEVD.Read(path);
            if (Uses(m)) return Fail($"event {id} already exists in, or is started by, {path}");
            idChecks.Add(new { file = Path.GetFileName(path), events = m.Events.Count, id_free = true });
        }
        var owned = comp.Events.Where(e => e.ID == id).ToList();
        if (owned.Count != 1) return Fail($"compiled file has {owned.Count} events {id}, need exactly one");
        var ev = owned[0];
        if (ev.RestBehavior != EMEVD.Event.RestBehaviorType.Restart) return Fail($"event {id} is {ev.RestBehavior}, need Restart");
        if (ev.Parameters.Count != 0) return Fail($"event {id} takes parameters; only InitializeEvent(0, id, 0) is supported");
        if (ev.Instructions.Any(IsInit)) return Fail($"event {id} starts other events; only one self-contained event is merged");
        var orig0 = orig.Events.FirstOrDefault(e => e.ID == 0);
        var comp0 = comp.Events.FirstOrDefault(e => e.ID == 0);
        if (orig0 == null || comp0 == null) return Fail("no event 0 in the original or compiled file");
        var inits = comp.Events.SelectMany(e => e.Instructions.Where(i => IsInit(i) && InitTarget(i) == id).Select(i => (e, i))).ToList();
        if (inits.Count != 1 || inits[0].e != comp0) return Fail($"need exactly one start of event {id}, in event 0; found {inits.Count}");
        var init = inits[0].i;
        var shape = new byte[12];
        BitConverter.TryWriteBytes(shape.AsSpan(4), id);
        if (init.ID != 0 || init.Layer != null || !init.ArgData.AsSpan().SequenceEqual(shape)
            || comp0.Parameters.Any(p => p.InstructionIndex == comp0.Instructions.IndexOf(init)))
            return Fail($"start of event {id} is not InitializeEvent(0, {id}, 0): {Ins(init)}");

        // SetCharacterTeamType (2004[02]): entity uint32, team uint8, three padding bytes.
        var teams = ev.Instructions.Select((i, k) => (i, k)).Where(x => x.i.Bank == 2004 && x.i.ID == 2)
            .Select(x => new { index = x.k, args = Convert.ToHexString(x.i.ArgData), shape_ok = x.i.ArgData.Length == 8 && x.i.ArgData[5..].All(b => b == 0),
                entity = x.i.ArgData.Length >= 4 ? BitConverter.ToUInt32(x.i.ArgData, 0) : 0, team = x.i.ArgData.Length >= 5 ? x.i.ArgData[4] : (byte)0 }).ToList();
        bool teamsOk = teams.All(t => t.shape_ok) && (expectTeams.Count == 0
            || teams.Select(t => t.team).Distinct().Order().SequenceEqual(expectTeams.Distinct().Order()));
        bool? entityOk = expectEntity == null ? null : teams.Count > 0 && teams.All(t => t.entity == expectEntity);

        // Event 0 ends early on some conditions (END IF instructions), so the start goes first, as
        // the compiler places it; parameter references in event 0 move with the shifted instructions.
        var merged = EMEVD.Read(origPath);
        var merged0 = merged.Events.Single(e => e.ID == 0);
        merged0.Instructions.Insert(0, new EMEVD.Instruction(2000, 0, shape));
        foreach (var p in merged0.Parameters) p.InstructionIndex++;
        merged.Events.Add(ev);
        Directory.CreateDirectory(Path.GetDirectoryName(full));
        merged.Write(outPath + ".partial", merged.Compression);

        // Re-read the original from disk and the written file, and compare everything.
        var fresh = EMEVD.Read(origPath);
        var back = EMEVD.Read(outPath + ".partial");
        var fileBad = new List<string>();
        if (back.Format != fresh.Format) fileBad.Add("format");
        if (Dcx(back.Compression) != Dcx(fresh.Compression)) fileBad.Add("compression");
        if (!back.StringData.AsSpan().SequenceEqual(fresh.StringData)) fileBad.Add("string data");
        if (!back.LinkedFileOffsets.SequenceEqual(fresh.LinkedFileOffsets)) fileBad.Add("linked file offsets");
        if (back.Events.Count != fresh.Events.Count + 1) fileBad.Add("event count");
        var eventsBad = fresh.Events.Where((e, k) => k >= back.Events.Count || !SameEvent(e, back.Events[k], e.ID == 0 ? 1 : 0))
            .Select(e => e.ID).ToList();
        var back0 = back.Events.FirstOrDefault(e => e.ID == 0);
        bool initOk = back0 != null && back0.Instructions.Count > 0 && Ins(back0.Instructions[0]) == Ins(init)
            && back.Events.Sum(e => e.Instructions.Count(i => IsInit(i) && InitTarget(i) == id)) == 1;
        bool eventOk = back.Events.Count(e => e.ID == id) == 1 && SameEvent(ev, back.Events[^1], 0);
        bool origKept = origHash == Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(origPath)));
        // Informational: game events the compiler re-encoded, which this merge leaves as the original's.
        var reencoded = fresh.Events.Where(e => e.ID != 0
            && !(comp.Events.FirstOrDefault(x => x.ID == e.ID) is EMEVD.Event c && SameEvent(e, c, 0))).Select(e => e.ID).ToList();

        bool ok = fileBad.Count == 0 && eventsBad.Count == 0 && initOk && eventOk && teamsOk && entityOk != false && origKept;
        if (ok) File.Move(outPath + ".partial", outPath, false);
        Console.WriteLine(JsonSerializer.Serialize(new
        {
            ok, event_id = id, rest = ev.RestBehavior.ToString(), event_name = ev.Name, instructions = ev.Instructions.Count,
            init = new { index = 0, instruction = Ins(init), ok = initOk }, event_kept = eventOk,
            team_commands = teams, expect_teams = expectTeams, teams_ok = teamsOk, expect_entity = expectEntity, entity_ok = entityOk,
            event_id_checks = idChecks,
            original_sha256 = origHash, original_unchanged = origKept, format = back.Format.ToString(), compression = Dcx(back.Compression),
            original_events = fresh.Events.Count, output_events = back.Events.Count,
            compiled_events_ignored = comp.Events.Where(e => e.ID != id && !fresh.Events.Any(f => f.ID == e.ID)).Select(e => e.ID),
            compiled_game_events_reencoded = reencoded.Count,
            collateral = new { file_metadata_changed = fileBad, events_changed = eventsBad },
            output = ok ? outPath : outPath + ".partial",
        }));
        return ok ? 0 : Fail("re-read verification failed; unverified .partial file left in place, nothing published");
    }
}
