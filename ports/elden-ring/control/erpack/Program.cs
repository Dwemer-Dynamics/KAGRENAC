// KAGRENAC erpack: original, bounded tool for the Elden Ring control package.
// Uses only the public SoulsFormats API from the user's own WitchyBND 3.0.1 release.
//   inspect  lists MSB enemies with their think/NPC param rows, LUAINFO entries, NPC teams,
//            think rows and action buttons
//   pack     adds one compiled Lua logic (+ LUAINFO/LUAGNL names) to a copy of aicommon.luabnd,
//            writes it as its own <id>_logic.luabnd laid out like a game per-logic file
//            and, in a copy of regulation.bin, clones one NpcThinkParam row (new logicId) and one
//            NpcParam row (new teamType) for the companion alone, then re-reads both
//   merge-events  adds one owned event and its InitializeEvent from a compiled common.emevd to
//            the game's original one, so no game event is re-encoded by the script compiler;
//            --check-events: map event files the id must also be free in; --expect-teams: the
//            teams SetCharacterTeamType may set (given with no value: none allowed);
//            --expect-entity: the one character every character AI call (2004[2/11/16/17/19/20])
//            must address
//   place    adds one copy of a template enemy, under a new entity id and name and with its own
//            think row, NpcParam row and backup animation, to a copy of a destination MSB beside
//            the grace named by a BonfireWarpParam row; refuses an id or
//            name already used in any given MSB or event file, then checks the written file is
//            the original plus only that part (and its model entry if the map lacked it)
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
                "place" => Place(opt),
                _ => Fail("usage: erpack inspect|pack|merge-events|place --option value ..."),
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
            Console.WriteLine($"npc {id} exists={npc.Rows.Any(r => r.ID == id)} team={npc.Rows.FirstOrDefault(r => r.ID == id)?["teamType"].Value}");
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
        public int npc_source { get; set; }
        public int npc_new { get; set; }
        public byte npc_team { get; set; }
        public string logic_layout { get; set; }
        public string out_dir { get; set; }
    }

    static int Pack(Dictionary<string, List<string>> o)
    {
        var s = JsonSerializer.Deserialize<Spec>(File.ReadAllText(One(o, "spec")));
        // Never overwrite: refuse before any write if a final or partial output is already there.
        var luaOut = Path.Combine(s.out_dir, "script", "aicommon.luabnd.dcx");
        var regOut = Path.Combine(s.out_dir, "regulation.bin");
        var each = $"{s.logic_id:D6}_logic";
        var eachOut = Path.Combine(s.out_dir, "script", each + ".luabnd.dcx");
        foreach (var p in new[] { luaOut, regOut, eachOut, luaOut + ".partial", regOut + ".partial", eachOut + ".partial" }.Where(Path.Exists))
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

        // <id>_logic.luabnd.dcx: in the user's archives 70 of the 84 logic ids used by think rows
        // have their own file of this name (the checked placed logics 10000, 410000 and 430000 do;
        // 14 ids have none). That the game loads a logic from it is not proven; as a packaging
        // hypothesis the logic also goes into one, laid out like the game's per-logic file given
        // as logic_layout: the same
        // container, entry ids, flags and folder naming, one .lua, one .luagnl, one .luainfo.
        var layout = BND4.Read(s.logic_layout);
        if (layout.Files.Count != 3 || layout.Files.Count(f => f.Name.EndsWith(".lua")) != 1
            || layout.Files.Count(f => f.Name.EndsWith(".luagnl")) != 1 || layout.Files.Count(f => f.Name.EndsWith(".luainfo")) != 1)
            return Fail("logic_layout is not a per-logic luabnd (one .lua, .luagnl and .luainfo); not guessing");
        var layoutInfo = LUAINFO.Read(layout.Files.Single(f => f.Name.EndsWith(".luainfo")).Bytes);
        if (layoutInfo.Goals.Count != 1 || !LogicShape(layoutInfo.Goals[0])) return Fail("logic_layout does not register exactly one logic");
        var layoutEach = $"{layoutInfo.Goals[0].ID:D6}_logic";
        if (!layout.Files.All(f => f.Name.Contains($"\\{layoutEach}\\{layoutEach}."))) return Fail($"logic_layout entries are not named {layoutEach}; not guessing");
        if (!layout.Files.Single(f => f.Name.EndsWith(".lua")).Bytes.Take(luaHeader.Length).SequenceEqual(luaHeader)) return Fail("logic_layout Lua entry has another header");
        foreach (var f in layout.Files)
        {
            var original = f.Name;
            f.Name = original.Replace($"\\{layoutEach}\\{layoutEach}.", $"\\{each}\\{each}.");
            if (original.EndsWith(".lua")) f.Bytes = code;
            else if (original.EndsWith(".luainfo")) { layoutInfo.Goals.Clear(); layoutInfo.Goals.Add(newGoal); f.Bytes = layoutInfo.Write(); }
            else { var g = LUAGNL.Read(f.Bytes); g.Globals.Clear(); g.Globals.AddRange(s.globals); f.Bytes = g.Write(); }
        }
        layout.Write(eachOut + ".partial", layout.Compression);

        // regulation.bin copy: clone the companion's think row; only logicId changes. battleGoalID
        // is kept for compatibility; the control logic does not queue it. Clone its NpcParam row
        // too; only teamType changes. The source rows, used by the original soldier, stay as they are.
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
        var npcFile = reg.Files.Single(f => Path.GetFileName(f.Name) == "NpcParam.param");
        var npc = PARAM.Read(npcFile.Bytes);
        npc.ApplyParamdef(PARAMDEF.XmlDeserialize(Path.Combine(s.paramdex, "NpcParam.xml")));
        var nsrc = npc.Rows.SingleOrDefault(r => r.ID == s.npc_source);
        if (nsrc == null) return Fail($"NpcParam {s.npc_source} not found");
        if (npc.Rows.Any(r => r.ID == s.npc_new)) return Fail($"NpcParam {s.npc_new} already exists");
        if (Convert.ToByte(nsrc["teamType"].Value) == s.npc_team) return Fail($"NpcParam {s.npc_source} already has team {s.npc_team}; nothing to clone");
        var nrow = new PARAM.Row(s.npc_new, "KAGRENAC companion", npc.AppliedParamdef);
        for (int i = 0; i < nsrc.Cells.Count; i++)
            nrow.Cells[i].Value = nsrc.Cells[i].Value is byte[] b ? b.Clone() : nsrc.Cells[i].Value;
        nrow["teamType"].Value = s.npc_team;
        npc.Rows.Add(nrow);
        npc.Rows.Sort((a, b) => a.ID.CompareTo(b.ID));
        npcFile.Bytes = npc.Write();
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
        PARAM ReadParam(BND4 r, string name, PARAMDEF def)
        {
            var t = PARAM.Read(r.Files.Single(f => Path.GetFileName(f.Name) == name + ".param").Bytes);
            t.ApplyParamdef(def);
            return t;
        }
        var think0 = ReadParam(reg0, "NpcThinkParam", think.AppliedParamdef);
        var think2 = ReadParam(reg2, "NpcThinkParam", think.AppliedParamdef);
        var r2 = think2.Rows.Single(r => r.ID == s.think_new);
        var s2 = think2.Rows.Single(r => r.ID == s.think_source);
        var differing = Enumerable.Range(0, r2.Cells.Count).Where(i => !Same(r2.Cells[i].Value, s2.Cells[i].Value)).ToList();
        var npc0 = ReadParam(reg0, "NpcParam", npc.AppliedParamdef);
        var npc2 = ReadParam(reg2, "NpcParam", npc.AppliedParamdef);
        var n2 = npc2.Rows.Single(r => r.ID == s.npc_new);
        var ns2 = npc2.Rows.Single(r => r.ID == s.npc_source);
        var npcDiffering = Enumerable.Range(0, n2.Cells.Count).Where(i => !Same(n2.Cells[i].Value, ns2.Cells[i].Value)).ToList();

        // Collateral: everything else must equal a fresh read of the inputs.
        bool SameFile(BinderFile a, BinderFile b, bool bytes) =>
            a.ID == b.ID && a.Name == b.Name && a.Flags == b.Flags && (!bytes || a.Bytes.AsSpan().SequenceEqual(b.Bytes));
        var regBad = reg2.Files.Count != reg0.Files.Count ? new List<string> { "file count" } : Enumerable.Range(0, reg0.Files.Count)
            .Where(i => !SameFile(reg0.Files[i], reg2.Files[i], Path.GetFileName(reg0.Files[i].Name) is not ("NpcThinkParam.param" or "NpcParam.param")))
            .Select(i => reg0.Files[i].Name).ToList();
        // Every other row of both params, the source rows included, equals the original.
        List<int> RowsBad(PARAM before, PARAM after, int added)
        {
            var rows = after.Rows.Where(r => r.ID != added).ToList();
            return rows.Count != before.Rows.Count ? new List<int> { -1 } : Enumerable.Range(0, rows.Count)
                .Where(i => rows[i].ID != before.Rows[i].ID || rows[i].Name != before.Rows[i].Name
                    || Enumerable.Range(0, rows[i].Cells.Count).Any(c => !Same(rows[i].Cells[c].Value, before.Rows[i].Cells[c].Value)))
                .Select(i => before.Rows[i].ID).ToList();
        }
        var rowsBad = RowsBad(think0, think2, s.think_new);
        var npcRowsBad = RowsBad(npc0, npc2, s.npc_new);
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
        // The per-logic file against a fresh read of its layout: same container, entries in the
        // same order with the same ids and flags, only the names' logic id and the contents new.
        var lay0 = BND4.Read(s.logic_layout);
        var each2 = BND4.Read(eachOut + ".partial");
        var eachBad = new List<string>();
        if (each2.Version != lay0.Version || each2.Format != lay0.Format || each2.Unicode != lay0.Unicode || each2.Extended != lay0.Extended
            || each2.BigEndian != lay0.BigEndian || each2.BitBigEndian != lay0.BitBigEndian || each2.Unk04 != lay0.Unk04 || each2.Unk05 != lay0.Unk05)
            eachBad.Add("container header");
        if (Dcx(each2.Compression) != Dcx(lay0.Compression)) eachBad.Add("compression");
        if (each2.Files.Count != lay0.Files.Count) eachBad.Add("file count");
        else for (int i = 0; i < lay0.Files.Count; i++)
        {
            var (a, b) = (lay0.Files[i], each2.Files[i]);
            if (a.ID != b.ID || a.Flags != b.Flags || b.Name != a.Name.Replace($"\\{layoutEach}\\{layoutEach}.", $"\\{each}\\{each}."))
                eachBad.Add("entry " + a.ID);
            else if (b.Name.EndsWith(".lua") && !b.Bytes.AsSpan().SequenceEqual(code)) eachBad.Add("lua bytes");
            else if (b.Name.EndsWith(".luainfo"))
            {
                var (i0, i2) = (LUAINFO.Read(a.Bytes), LUAINFO.Read(b.Bytes));
                if (i2.Goals.Count != 1 || !Goal(i2.Goals[0], newGoal) || i2.BigEndian != i0.BigEndian || i2.LongFormat != i0.LongFormat) eachBad.Add("luainfo");
            }
            else if (b.Name.EndsWith(".luagnl"))
            {
                var (g0, g2) = (LUAGNL.Read(a.Bytes), LUAGNL.Read(b.Bytes));
                if (!g2.Globals.SequenceEqual(s.globals) || g2.BigEndian != g0.BigEndian || g2.LongFormat != g0.LongFormat) eachBad.Add("luagnl");
            }
        }
        bool containers = containerBad.Count == 0;

        bool ok = entry.Bytes.SequenceEqual(code) && entry.Name == dir + s.lua_file && entry.Flags == game[0].Flags
            && entryAt == fileAt && goalOk
            && s.globals.All(gnl2.Globals.Contains) && (int)r2["logicId"].Value == s.logic_id
            && Equals(r2["battleGoalID"].Value, s2["battleGoalID"].Value)
            && differing.Select(i => r2.Cells[i].Def.InternalName).SequenceEqual(new[] { "logicId" })
            && Convert.ToByte(n2["teamType"].Value) == s.npc_team
            && npcDiffering.Select(i => n2.Cells[i].Def.InternalName).SequenceEqual(new[] { "teamType" })
            && regBad.Count == 0 && rowsBad.Count == 0 && npcRowsBad.Count == 0 && luaBad.Count == 0 && goalsKept && globalsKept && containers
            && eachBad.Count == 0;
        if (ok)
        {
            File.Move(luaOut + ".partial", luaOut, false);
            File.Move(regOut + ".partial", regOut, false);
            File.Move(eachOut + ".partial", eachOut, false);
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
            npc_row = s.npc_new, npc_cell_diffs = npcDiffering.Select(i => new { name = n2.Cells[i].Def.InternalName,
                value = Show(n2.Cells[i].Value), source = Show(ns2.Cells[i].Value) }),
            collateral = new { regulation_files_changed = regBad, think_rows_changed = rowsBad, npc_rows_changed = npcRowsBad, luabnd_files_changed = luaBad,
                luainfo_goals_kept = goalsKept, luagnl_globals_kept = globalsKept, container_metadata_changed = containerBad },
            logic_file = new { layout = Path.GetFileName(s.logic_layout), names = each2.Files.Select(f => $"{f.ID} {f.Flags} {f.Name}"),
                compression = Dcx(each2.Compression), differences_from_layout = eachBad, ok = eachBad.Count == 0 },
            outputs = ok ? new[] { luaOut, regOut, eachOut } : new[] { luaOut + ".partial", regOut + ".partial", eachOut + ".partial" },
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
        var expectTeams = o.ContainsKey("expect-teams") ? o["expect-teams"].Select(byte.Parse).ToList() : null;
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
        bool teamsOk = teams.All(t => t.shape_ok) && (expectTeams == null
            || teams.Select(t => t.team).Distinct().Order().SequenceEqual(expectTeams.Distinct().Order()));
        // Character AI calls (team, event target, clear target, AI command, AI id, replan): the
        // character is the first argument of each.
        var aiCalls = ev.Instructions.Where(i => i.Bank == 2004 && i.ID is 2 or 11 or 16 or 17 or 19 or 20)
            .Select(i => new { instruction = $"2004[{i.ID}]", entity = i.ArgData.Length >= 4 ? BitConverter.ToUInt32(i.ArgData, 0) : 0 }).ToList();
        bool? entityOk = expectEntity == null ? null : aiCalls.Count > 0 && aiCalls.All(c => c.entity == expectEntity);

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
            ai_calls = aiCalls.GroupBy(c => (c.instruction, c.entity)).Select(g => new { g.Key.instruction, g.Key.entity, count = g.Count() }),
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

    // Public values of an MSB entry, nested settings objects and arrays flattened, so two
    // entries compare field by field.
    static Dictionary<string, string> Fields(object o, string pre = "", int depth = 0)
    {
        var d = new Dictionary<string, string>();
        foreach (var p in o.GetType().GetProperties().Where(p => p.GetIndexParameters().Length == 0))
        {
            var v = p.GetValue(o);
            if (v == null || v is string || v.GetType().IsPrimitive || v.GetType().IsEnum || v is System.Numerics.Vector3) d[pre + p.Name] = v?.ToString() ?? "null";
            else if (v is System.Collections.IEnumerable e) d[pre + p.Name] = string.Join(",", e.Cast<object>());
            else if (depth < 3) foreach (var kv in Fields(v, pre + p.Name + ".", depth + 1)) d[kv.Key] = kv.Value;
            else d[pre + p.Name] = "unread";
        }
        return d;
    }

    // Every offset, not only aligned ones, so any stored copy of the value counts as a use.
    static int Occurrences(byte[] data, byte[] value)
    {
        int n = 0;
        for (int i = data.AsSpan().IndexOf(value); i >= 0; )
        {
            n++;
            int next = data.AsSpan(i + 1).IndexOf(value);
            i = next < 0 ? -1 : i + 1 + next;
        }
        return n;
    }

    static float Flat(System.Numerics.Vector3 a, System.Numerics.Vector3 b) => MathF.Sqrt((a.X - b.X) * (a.X - b.X) + (a.Z - b.Z) * (a.Z - b.Z));

    static IEnumerable<IMsbEntry> Entries(MSBE m) =>
        m.Models.GetEntries().Concat<IMsbEntry>(m.Events.GetEntries()).Concat(m.Regions.GetEntries()).Concat(m.Routes.GetEntries()).Concat(m.Parts.GetEntries());

    // One copy of a template enemy beside a grace. The grace comes from the user's own
    // BonfireWarpParam row (name from the Paramdex names file, tile from areaNo/gridXNo/gridZNo,
    // landmark = the one destination asset at the row's position, bonfire entity registered by
    // RegisterBonfire 2009[03] in the tile's events); the height is checked against that landmark
    // and the nearest player part (a warp spawn). Nothing about the grace is guessed or fixed here.
    static int Place(Dictionary<string, List<string>> o)
    {
        string tplPath = One(o, "template"), destPath = One(o, "dest"), outPath = One(o, "out"), name = One(o, "name");
        uint tplId = uint.Parse(One(o, "template-entity")), id = uint.Parse(One(o, "entity"));
        int row = int.Parse(One(o, "bonfire-row"));
        string wantName = One(o, "bonfire-name");
        var inv = System.Globalization.CultureInfo.InvariantCulture;
        var pv = o.GetValueOrDefault("pos") ?? new List<string>();
        if (pv.Count != 3) return Fail("need --pos x y z");
        var pos = new System.Numerics.Vector3(float.Parse(pv[0], inv), float.Parse(pv[1], inv), float.Parse(pv[2], inv));
        if (!float.IsFinite(pos.X) || !float.IsFinite(pos.Y) || !float.IsFinite(pos.Z)) return Fail("position is not finite");
        float F(string k) => float.Parse(One(o, k), inv);
        int think = int.Parse(One(o, "think")), npcRow = int.Parse(One(o, "npc")), backupAnim = int.Parse(One(o, "backup-anim"));
        float offMin = F("offset-min"), offMax = F("offset-max"), maxDy = F("max-dy"), clearChr = F("clear-chr"), clearAsset = F("clear-asset"), clearRegion = F("clear-region");
        var checkMsbs = o.GetValueOrDefault("check-msb") ?? new List<string>();
        var checkEvents = o.GetValueOrDefault("check-events") ?? new List<string>();
        bool Listed(List<string> l, string p) => l.Any(x => Path.GetFullPath(x).Equals(Path.GetFullPath(p), StringComparison.OrdinalIgnoreCase));
        if (!Listed(checkMsbs, tplPath) || !Listed(checkMsbs, destPath)) return Fail("--check-msb must include the template and destination MSBs");
        if (!Listed(checkEvents, One(o, "dest-events"))) return Fail("--check-events must include the destination's event file");
        foreach (var p in new[] { outPath, outPath + ".partial" }.Where(Path.Exists))
            return Fail("output already exists, refusing to overwrite: " + p);
        var full = Path.GetFullPath(outPath);
        if (checkMsbs.Concat(checkEvents).Append(tplPath).Append(destPath).Any(p => Path.GetFullPath(p).Equals(full, StringComparison.OrdinalIgnoreCase)))
            return Fail("--out must be a new path, not an input");
        string Hash(string p) => Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(p)));
        var inputHashes = checkMsbs.Concat(checkEvents).Append(tplPath).Append(destPath).Select(Path.GetFullPath)
            .Distinct(StringComparer.OrdinalIgnoreCase).ToDictionary(p => p, Hash);

        // The grace, from the user's regulation and the Paramdex names.
        var names = File.ReadAllLines(One(o, "bonfire-names")).Where(l => l.StartsWith(row + " ")).ToList();
        if (names.Count != 1 || names[0][(row.ToString().Length + 1)..] != wantName) return Fail($"BonfireWarpParam {row} is not named '{wantName}' in the names file");
        var reg = RegulationDecryptor.DecryptERRegulation(One(o, "regulation"));
        var bw = LoadParam(reg, One(o, "paramdex"), "BonfireWarpParam").Rows.SingleOrDefault(r => r.ID == row);
        if (bw == null) return Fail($"BonfireWarpParam {row} not in regulation.bin");
        var tile = $"m{bw["areaNo"].Value:00}_{bw["gridXNo"].Value:00}_{bw["gridZNo"].Value:00}_00";
        var destTile = Path.GetFileName(destPath).Split('.')[0];
        if (destTile != tile) return Fail($"BonfireWarpParam {row} is on {tile}, not {destTile}");
        var warp = new System.Numerics.Vector3((float)bw["posX"].Value, (float)bw["posY"].Value, (float)bw["posZ"].Value);
        uint bonfire = (uint)bw["bonfireEntityId"].Value;
        var destEvents = One(o, "dest-events");
        if (Path.GetFileName(destEvents).Split('.')[0] != tile) return Fail($"--dest-events must be {tile}'s event file");
        var registers = EMEVD.Read(destEvents).Events.SelectMany(e => e.Instructions.Select((i, k) => (e, i, k)))
            .Where(x => x.i.Bank == 2009 && x.i.ID == 3 && x.i.ArgData.Length >= 24 && BitConverter.ToUInt32(x.i.ArgData, 4) == bonfire).ToList();
        if (registers.Count != 1) return Fail($"bonfire entity {bonfire} is registered {registers.Count} times (RegisterBonfire 2009[03]) in {tile}'s events, need one");
        var rb = registers[0];

        var dest = MSBE.Read(destPath);
        var marks = dest.Parts.Assets.Where(a => MathF.Abs(a.Position.X - warp.X) < 0.01f && MathF.Abs(a.Position.Y - warp.Y) < 0.01f && MathF.Abs(a.Position.Z - warp.Z) < 0.01f).ToList();
        if (marks.Count != 1) return Fail($"{marks.Count} assets at BonfireWarpParam {row}'s position {warp} in {tile}, need exactly one");
        var mark = marks[0];
        var spawn = dest.Parts.Players.Where(p => Flat(p.Position, mark.Position) <= 5).OrderBy(p => Flat(p.Position, mark.Position)).FirstOrDefault();
        if (spawn == null) return Fail("no player part within 5 m of the grace to check the height against");

        // The place: beside the grace, at its height, clear of characters, assets and event areas.
        float off = Flat(pos, mark.Position);
        if (off < offMin || off > offMax) return Fail($"position is {off:F2} m from the grace, need {offMin}..{offMax}");
        if (MathF.Abs(pos.Y - mark.Position.Y) > maxDy || MathF.Abs(pos.Y - spawn.Position.Y) > maxDy)
            return Fail($"height {pos.Y} is more than {maxDy} m from the grace ({mark.Position.Y}) or the player part {spawn.Name} ({spawn.Position.Y})");
        var tooClose = dest.Parts.Enemies.Cast<MSBE.Part>().Concat(dest.Parts.Players).Concat(dest.Parts.DummyEnemies).Where(p => Flat(p.Position, pos) < clearChr)
            .Concat(dest.Parts.Assets.Cast<MSBE.Part>().Concat(dest.Parts.DummyAssets).Where(p => Flat(p.Position, pos) < clearAsset))
            .Select(p => $"{p.Name} {Flat(p.Position, pos):F2} m").ToList();
        if (tooClose.Count > 0) return Fail("position too close to " + string.Join(", ", tooClose));
        // Event-addressed areas (entity id set): outside each, with a margin, on the ground plane.
        // A box counts by its corner radius, so its rotation does not matter; any other shape
        // within 30 m is refused unchecked.
        bool Inside(MSBE.Region r) => Flat(pos, r.Position) < clearRegion + r.Shape switch
        {
            MSB.Shape.Point => 0,
            MSB.Shape.Sphere s => s.Radius,
            MSB.Shape.Cylinder c => c.Radius,
            MSB.Shape.Box b => MathF.Sqrt(b.Width * b.Width + b.Depth * b.Depth) / 2,
            _ => 30,
        };
        var inRegions = dest.Regions.GetEntries().Where(r => r.EntityID != 0 && Inside(r)).Select(r => $"{r.GetType().Name} {r.EntityID} {r.Shape.GetType().Name}").ToList();
        if (inRegions.Count > 0) return Fail("position inside (or unchecked shape of) event regions: " + string.Join(", ", inRegions));

        // The template and its references.
        var tpl = MSBE.Read(tplPath);
        var src = tpl.Parts.Enemies.Where(e => e.EntityID == tplId).ToList();
        if (src.Count != 1) return Fail($"template entity {tplId} found {src.Count} times in {Path.GetFileName(tplPath)}");
        var t = src[0];
        var tm = tpl.Models.Enemies.SingleOrDefault(m => m.Name == t.ModelName);
        if (tm == null) return Fail($"template model {t.ModelName} not registered in its own MSB");
        if (!System.Text.RegularExpressions.Regex.IsMatch(name, $"^{t.ModelName}_\\d{{4}}$")) return Fail($"name must be {t.ModelName}_NNNN");
        // Any other name reference (collision, patrol route, ...) would point into the template's map.
        var refs = t.GetType().GetProperties().Where(p => p.PropertyType == typeof(string) && p.Name is not ("Name" or "ModelName" or "SibPath"))
            .Select(p => (p.Name, v: (string)p.GetValue(t))).Where(x => !string.IsNullOrEmpty(x.v)).ToList();
        if (refs.Count > 0) return Fail("template references " + string.Join(", ", refs.Select(r => $"{r.Name}={r.v}")) + "; not guessing a destination reference");
        if (t.TileLoad.MapID.Any(b => b != 255)) return Fail("template has a tile-load map reference; not guessing one for the destination");

        // The id and name must be new everywhere given: any byte offset of every MSB and event file,
        // and every entry name of every MSB (also as raw UTF-16).
        var idBytes = BitConverter.GetBytes(id);
        var nameBytes = System.Text.Encoding.Unicode.GetBytes(name + "\0");
        var idUses = new List<string>();
        foreach (var p in checkMsbs)
        {
            var raw = DCX.Decompress(p);
            int n = Occurrences(raw, idBytes), m = Occurrences(raw, nameBytes);
            if (n > 0 || m > 0) idUses.Add($"{Path.GetFileName(p)}: id {n}x, name {m}x");
            if (Entries(MSBE.Read(p)).Any(e => string.Equals(e.Name, name, StringComparison.OrdinalIgnoreCase))) idUses.Add($"{Path.GetFileName(p)}: entry named {name}");
        }
        foreach (var p in checkEvents)
        {
            int n = Occurrences(DCX.Decompress(p), idBytes);
            if (n > 0 || EMEVD.Read(p).Events.Any(e => e.ID == id)) idUses.Add($"{Path.GetFileName(p)}: id {n}x");
        }
        if (idUses.Count > 0) return Fail($"entity {id} or name {name} already used: " + string.Join("; ", idUses));

        // The copy: only name, instance, entity id, position, the template map's entity groups, and
        // its own think row, NpcParam row and backup animation change.
        var copy = (MSBE.Part.Enemy)t.DeepCopy();
        copy.ThinkParamID = think;
        copy.NPCParamID = npcRow;
        copy.BackupEventAnimID = backupAnim;
        copy.Name = name;
        copy.InstanceID = int.Parse(name[(t.ModelName.Length + 1)..]);
        copy.EntityID = id;
        copy.Position = pos;
        for (int i = 0; i < copy.EntityGroupIDs.Length; i++) copy.EntityGroupIDs[i] = 0;
        bool Sorted<T>(List<T> l) where T : IMsbEntry => l.Zip(l.Skip(1)).All(p => string.CompareOrdinal(p.First.Name, p.Second.Name) < 0);
        int At<T>(List<T> l, string n) where T : IMsbEntry => Sorted(l) ? l.Count(x => string.CompareOrdinal(x.Name, n) < 0) : l.Count;
        bool modelAdded = !dest.Models.Enemies.Any(m => m.Name == t.ModelName);
        if (modelAdded) dest.Models.Enemies.Insert(At(dest.Models.Enemies, tm.Name), (MSBE.Model.Enemy)tm.DeepCopy());
        int partAt = At(dest.Parts.Enemies, name);
        dest.Parts.Enemies.Insert(partAt, copy);
        Directory.CreateDirectory(Path.GetDirectoryName(full));
        dest.Write(outPath + ".partial", dest.Compression);

        // Re-read: exactly the one part (and model) added; with them removed, the file is the
        // user's original byte for byte (decompressed); the inputs are unchanged.
        var back = MSBE.Read(outPath + ".partial");
        var fresh = MSBE.Read(destPath);
        var owned = back.Parts.GetEntries().Where(e => e.Name == name).ToList();
        var ownedPart = owned.Count == 1 ? owned[0] as MSBE.Part.Enemy : null;
        var ownedModels = back.Models.Enemies.Where(m => m.Name == t.ModelName).ToList();
        bool countsOk = back.Parts.GetEntries().Count == fresh.Parts.GetEntries().Count + 1
            && back.Models.GetEntries().Count == fresh.Models.GetEntries().Count + (modelAdded ? 1 : 0)
            && back.Regions.GetEntries().Count == fresh.Regions.GetEntries().Count && back.Events.GetEntries().Count == fresh.Events.GetEntries().Count
            && back.Routes.GetEntries().Count == fresh.Routes.GetEntries().Count && ownedPart != null && ownedModels.Count == 1;
        var allowed = new HashSet<string> { "Name", "InstanceID", "EntityID", "Position", "EntityGroupIDs", "ThinkParamID", "NPCParamID", "BackupEventAnimID" };
        var ft = Fields(t);
        var fo = ownedPart == null ? new Dictionary<string, string>() : Fields(ownedPart);
        var differing = ft.Keys.Union(fo.Keys).Where(k => ft.GetValueOrDefault(k) != fo.GetValueOrDefault(k)).OrderBy(k => k).ToList();
        bool copyOk = ownedPart != null && differing.All(allowed.Contains) && ownedPart.EntityID == id && ownedPart.Position == pos
            && ownedPart.EntityGroupIDs.All(g => g == 0) && back.Parts.Enemies.IndexOf(ownedPart) == partAt
            && ownedPart.ThinkParamID == think && ownedPart.NPCParamID == npcRow && ownedPart.BackupEventAnimID == backupAnim;
        bool modelOk = ownedModels.Count == 1 && Fields(ownedModels[0]).OrderBy(k => k.Key).SequenceEqual(Fields(tm).OrderBy(k => k.Key));
        var outRaw = DCX.Decompress(outPath + ".partial");
        int idInOutput = Occurrences(outRaw, idBytes);
        if (ownedPart != null) back.Parts.Enemies.Remove(ownedPart);
        if (modelAdded && ownedModels.Count == 1) back.Models.Enemies.Remove(ownedModels[0]);
        bool originalKept = DCX.Decompress(back.Write()).AsSpan().SequenceEqual(DCX.Decompress(destPath));
        bool sameCompression = Dcx(MSBE.Read(outPath + ".partial").Compression) == Dcx(fresh.Compression);
        var inputsChanged = inputHashes.Where(kv => Hash(kv.Key) != kv.Value).Select(kv => Path.GetFileName(kv.Key)).ToList();

        bool ok = countsOk && copyOk && modelOk && idInOutput == 1 && originalKept && sameCompression && inputsChanged.Count == 0;
        if (ok) File.Move(outPath + ".partial", outPath, false);
        string V(System.Numerics.Vector3 v) => $"{v.X.ToString(inv)}, {v.Y.ToString(inv)}, {v.Z.ToString(inv)}";
        Console.WriteLine(JsonSerializer.Serialize(new
        {
            ok,
            grace = new
            {
                bonfire_warp_row = row, name = wantName, tile, warp_position = V(warp), bonfire_entity = bonfire,
                register_bonfire = new { @event = rb.e.ID, index = rb.k, flag = BitConverter.ToUInt32(rb.i.ArgData, 0),
                    reaction_distance = BitConverter.ToSingle(rb.i.ArgData, 8), enemy_deactivation_distance = BitConverter.ToSingle(rb.i.ArgData, 20) },
                landmark = new { mark.Name, model = mark.ModelName, entity = mark.EntityID, position = V(mark.Position), rotation_y = mark.Rotation.Y },
                height_reference = new { spawn.Name, model = spawn.ModelName, entity = spawn.EntityID, position = V(spawn.Position), distance = Flat(spawn.Position, mark.Position) },
            },
            placed = new
            {
                name, entity = id, position = V(pos), rotation = V(copy.Rotation), from_grace_m = off,
                dx = pos.X - mark.Position.X, dz = pos.Z - mark.Position.Z, dy_grace = pos.Y - mark.Position.Y, dy_spawn = pos.Y - spawn.Position.Y,
                nearest = dest.Parts.GetEntries().Where(p => p is MSBE.Part.Enemy or MSBE.Part.Player or MSBE.Part.Asset or MSBE.Part.DummyAsset && p.Name != name)
                    .OrderBy(p => Flat(p.Position, pos)).Take(6).Select(p => $"{p.Name} {Flat(p.Position, pos):F2} m"),
            },
            template = new { file = Path.GetFileName(tplPath), t.Name, entity = tplId, model = t.ModelName, think = t.ThinkParamID, npc = t.NPCParamID, talk = t.TalkID, backup_anim = t.BackupEventAnimID,
                entity_groups_cleared = t.EntityGroupIDs.Where(g => g != 0), collision = t.CollisionPartName, walk_route = t.WalkRouteName },
            fields_differing_from_template = differing.Select(k => new { field = k, template = ft.GetValueOrDefault(k), copy = fo.GetValueOrDefault(k) }),
            model_added = modelAdded, model_entry_ok = modelOk, part_index = partAt, counts_ok = countsOk, copy_ok = copyOk,
            id_and_name_free_in = checkMsbs.Concat(checkEvents).Select(Path.GetFileName), id_in_output = idInOutput,
            original_entries_unchanged = originalKept, same_compression = sameCompression, inputs_changed = inputsChanged,
            output = ok ? outPath : outPath + ".partial",
        }));
        return ok ? 0 : Fail("re-read verification failed; unverified .partial file left in place, nothing published");
    }
}
