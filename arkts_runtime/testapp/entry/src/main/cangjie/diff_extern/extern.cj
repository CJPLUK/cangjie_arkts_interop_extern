package ohos_app_cangjie_entry.diff_extern

import std.collection.ArrayList
import std.runtime.gc
import std.sync.{AtomicBool, AtomicInt64, Barrier}
import arkts_runtime.*
import ohos_app_cangjie_entry.difflog.*

type E = Extern<ArkTSRuntime>

func from<T>(x: E): T { ArkTSRuntime.fromExtern<T>(x) }

func to<T>(x: T): E { ArkTSRuntime.toExtern<T>(x) }

func num(x: E): Float64 { ArkTSRuntime.fromExtern<Float64>(x) }

func str(x: E): String { ArkTSRuntime.fromExtern<String>(x) }

func fn(body: (Array<E>) -> E): E { ArkTSRuntime.function(body) }

func same(a: E, b: E): Bool { ArkTSRuntime.strictEqual(a, b) }

func attempt(log: Transcript, label: String, fragment: String, body: () -> Any): Unit {
    let outcome = try {
        body()
        "ok"
    } catch (e: ForeignRuntimeException) {
        "js:${e.toString().contains(fragment)}"
    } catch (_: ExternMemberAccessException) {
        "member"
    } catch (_: ExternFunctionAccessException) {
        "function"
    } catch (_: ExternConversionException) {
        "conversion"
    } catch (_: ExternIndexedAccessException) {
        "index"
    } catch (e: Exception) {
        "other:${e}"
    }
    log.text(label, outcome)
}

public func runProgram(name: String, offThread: Bool): String {
    let log = Transcript()
    try {
        let w = ArkTSRuntime.global().__diffWorld
        match (name) {
            case "objectGraph" => objectGraph(w, log)
            case "internChurn" => internChurn(w, log)
            case "numbers" => numbers(w, log)
            case "strings" => strings(w, log)
            case "arrays" => arrays(w, log)
            case "methodsAndThis" => methodsAndThis(w, log)
            case "callbacks" => callbacks(w, log)
            case "exceptions" => exceptions(w, log)
            case "builtins" => builtins(w, log)
            case "longTurn" => longTurn(w, log)
            case "gcChurn" => gcChurn(w, log)
            case "jsonWalk" => jsonWalk(w, log)
            case "options" => options(w, log)
            case "manyThreads" => manyThreads(w, log, offThread)
            case _ => log.text("unknown program", name)
        }
    } catch (e: Exception) {
        log.text("uncaught", e.toString())
    }
    log.render()
}

func objectGraph(w: E, log: Transcript): Unit {
    let r = w.root
    log.num("d", num(r.a.b.c.d))
    r.a.b.c.d = 2.5
    log.num("d after write", num(r.a.b.c.d))
    log.bool("a read twice is one object", same(r.a, r.a))
    let oldB = r.a.b
    let nb = ArkTSRuntime.object()
    nb.c = ArkTSRuntime.object()
    nb.c.d = 7.0
    r.a.b = nb
    log.num("d via new b", num(r.a.b.c.d))
    log.bool("b replaced", same(oldB, r.a.b))
    log.num("old b still readable", num(oldB.c.d))
    let a = r.a
    r.a = r.x
    r.x = a
    log.str("a.tag after swap", str(r.a.tag))
    log.num("x.b.c.d after swap", num(r.x.b.c.d))
    r.self = r
    log.bool("cycle", same(r.self.self.self, r))
    r.x = ArkTSRuntime.undefined()
    log.bool("x undefined", ArkTSRuntime.isUndefined(r.x))
    log.text("keys", String.join(ArkTSRuntime.objectKeys(r), delimiter: ","))
}

func internChurn(w: E, log: Transcript): Unit {
    var sum = 0.0
    var wrongId = 0.0
    var sameAsBefore = 0.0
    for (i in 1..=300) {
        let before = w.holder.slot
        w.rotate(Float64(i))
        let after = w.holder.slot
        if (num(after.id) != Float64(i)) { wrongId += 1.0 }
        if (same(before, after)) { sameAsBefore += 1.0 }
        sum += num(after.id)
    }
    log.num("sum", sum)
    log.num("wrong ids", wrongId)
    log.num("same as before", sameAsBefore)
    var total = 0.0
    for (_ in 0..3) {
        for (k in 0..600) { total += num(w.many[k].child.v) }
    }
    log.num("many total", total)
    let first = w.many[0].child
    w.mutateMany()
    total = 0.0
    for (k in 0..600) { total += num(w.many[k].child.v) }
    log.num("many total after JS mutation", total)
    log.bool("replaced child differs", same(first, w.many[0].child))
    let kept = w.many[0].child
    for (k in 0..600) { total += num(w.many[k].child.v) }
    log.bool("identity after 600 other receivers", same(kept, w.many[0].child))
    log.bool("different receivers differ", same(w.many[1].child, w.many[2].child))
    w.holder.slot = w.many[5].child
    log.bool("slot set from another read", same(w.holder.slot, w.many[5].child))
    w.holder.slot = 3.0
    log.num("slot as number", num(w.holder.slot))
    w.holder.slot = w.many[7].child
    log.num("slot back to object", num(w.holder.slot.v))
    w.many[7].child.v = -1.0
    log.num("write through other path", num(w.holder.slot.v))
}

func numbers(w: E, log: Transcript): Unit {
    let count = Int64(num(w.vals.length))
    for (i in 0..count) {
        let x = num(w.vals[i])
        log.num("v${i}", x)
        let y = x * 3.0 + 1.0
        w.out.v = y
        log.num("v${i} written", num(w.out.v))
        log.num("v${i} echo", num(w.echo(y)))
        let int32 = try { from<Int32>(w.vals[i]).toString() } catch (_: ExternConversionException) { "conversion" }
        log.text("v${i} Int32", int32)
        log.num("v${i} Float32", Float64(from<Float32>(w.vals[i])))
    }
    w.out.big = 9007199254740993
    log.text("Int64 written kind", str(w.kind(w.out.big)))
    log.text("Int64 read", from<Int64>(w.out.big).toString())
    w.out.min = Int64.Min
    log.text("Int64.Min read", from<Int64>(w.out.min).toString())
    attempt(log, "Int64 from a number", "", { => from<Int64>(w.vals[0]) })
    w.out.i32 = Int32.Max
    log.text("Int32 written kind", str(w.kind(w.out.i32)))
    log.num("sum", num(w.sum(0.1, 0.2)))
    log.num("sum of extremes", num(w.sum(w.vals[7], w.vals[7])))
}

func strings(w: E, log: Transcript): Unit {
    let count = Int64(num(w.strs.length))
    for (i in 0..count) {
        let s = str(w.strs[i])
        if (!wellFormed(s)) {
            log.text("s${i}", "malformed")
            continue
        }
        log.str("s${i}", s)
        log.num("s${i} js length", num(w.len(w.strs[i])))
        let t = s + "|" + s
        w.out.s = t
        log.num("s${i} written length", num(w.len(w.out.s)))
        log.str("s${i} echo", str(w.echo(t)))
        log.bool("s${i} round trip", str(w.out.s) == t)
    }
    attempt(log, "member read on a string", "", { => w.strs[1].length })
    w.out["kéy"] = 1.0
    w.out[""] = 2.0
    log.text("keys", String.join(ArkTSRuntime.objectKeys(w.out).map({ k => fmtStr(k) }), delimiter: ","))
    log.num("index by unicode key", num(w.out["kéy"]))
}

func arrays(w: E, log: Transcript): Unit {
    let a = w.arr
    log.num("length", num(a.length))
    for (i in 0..7) { log.text("kind ${i}", str(w.kind(a[i]))) }
    attempt(log, "out of bounds", "", { => a[100] })
    a[10] = "far"
    log.num("length after far write", num(a.length))
    log.text("hole", str(w.kind(a[8])))
    a.length = 3.0
    log.num("length after shrink", num(a.length))
    attempt(log, "element past shrink", "", { => a[5] })
    log.num("push", num(a.push(42.0)))
    log.num("indexOf", num(a.indexOf(42.0)))
    log.str("Float64 index", str(a[1.0]))
    log.bool("String index", from<Bool>(a["2"]))
    log.num("nested", num(w.nested[1][1][0]))
    w.nested[1][1][1] = 50.0
    log.num("nested write", num(w.nested[1][1][1]))
    let json = ArkTSRuntime.global().JSON
    w.out.floats = [1.5, 2.5]
    log.str("Array<Float64> written", str(json.stringify(w.out.floats)))
    w.out.strs = ["x", "y"]
    log.str("Array<String> written", str(json.stringify(w.out.strs)))
    w.out.opts = [Some(1.0), None<Float64>]
    log.str("Array<?Float64> written", str(json.stringify(w.out.opts)))
    w.out.nested = [[1.0, 2.0], [3.0]]
    log.str("Array<Array<Float64>> written", str(json.stringify(w.out.nested)))
    var total = 0.0
    for (x in from<Array<Float64>>(w.nums)) { total += x }
    log.num("Array<Float64> read sum", total)
    w.nums.sort()
    log.str("default sort", str(w.nums.join(",")))
    w.nums.reverse()
    log.str("reverse", str(w.nums.join(",")))
    log.num("Array.isArray", if (from<Bool>(ArkTSRuntime.global().Array.isArray(w.nums))) { 1.0 } else { 0.0 })
}

func methodsAndThis(w: E, log: Transcript): Unit {
    let c = w.c
    log.num("inc 2", num(c.inc(2.0)))
    log.num("inc 3", num(c.inc(3.0)))
    log.num("getter", num(c.double))
    c.value = 4.0
    log.num("after setter", num(c.count))
    let inc = c.inc
    log.num("extracted method keeps this", num(inc(1.0)))
    log.num("static", num(w.Counter.make().inc(5.0)))
    log.text("method this", str(w.whoAmI()))
    let who = w.whoAmI
    log.text("extracted function this", str(who()))
    log.num("index call", num(c["inc"](1.0)))
    let c2 = ArkTSRuntime.global().Reflect.construct(w.Counter, to(Array<E>()))
    log.num("Reflect.construct", num(c2.inc(7.0)))
    log.bool("shared prototype method", same(c.inc, c2.inc))
    log.bool("instances differ", same(c, c2))
    let next = w.makeCounter()
    next()
    next()
    log.num("closure", num(next()))
    log.text("own keys", String.join(ArkTSRuntime.objectKeys(c), delimiter: ","))
}

func wellFormed(s: String): Bool {
    try {
        for (_ in s.runes()) {}
        true
    } catch (_: IllegalArgumentException) {
        false
    }
}

class Cell {
    var value = 0.0
}

func callbacks(w: E, log: Transcript): Unit {
    log.num("apply", num(w.apply(fn({ args => to(num(args[0]) * num(args[0])) }), 7.0)))
    log.num("twice", num(w.twice(fn({ args => to(num(args[0]) + 10.0) }))))
    log.str("map", str(w.nums.map(fn({ args => to(num(args[0]) * 10.0) })).join(",")))
    log.str("sort", str(w.nums.slice().sort(fn({ args => to(num(args[0]) - num(args[1])) })).join(",")))
    log.num("reenter", num(w.reenter(fn({ args => to(num(w.inner(args[0])) + 5.0) }))))
    log.str("callback throws", str(w.callAndCatch(fn({ _ => throw Exception("cbBoom") }))))
    log.str("callback returns string", str(w.apply(fn({ args => to(str(args[0]) + "!") }), "hi")))
    log.text("callback returns undefined", str(w.kind(w.apply(fn({ _ => ArkTSRuntime.undefined() }), 0.0))))
    let count = Cell()
    w.nums.forEach(fn({ _ =>
        count.value += 1.0
        ArkTSRuntime.undefined()
    }))
    log.num("forEach count", count.value)
    w.apply(fn({ args =>
        args[0].touched = true
        args[0]
    }), w.target)
    log.bool("callback mutated its argument", from<Bool>(w.target.touched))
    log.num("reduce over 5000",
        num(w.range.reduce(fn({ args => to(num(args[0]) + num(args[1])) }), 0.0)))
    let seen = Cell()
    let f = fn({ args =>
        seen.value += num(args[0])
        to(seen.value)
    })
    w.apply(f, 1.0)
    w.apply(f, 2.0)
    log.num("one function called twice", num(w.apply(f, 3.0)))
}

func exceptions(w: E, log: Transcript): Unit {
    attempt(log, "Error", "E-boom", { => w.boom() })
    attempt(log, "thrown string", "E-str", { => w.throwStr() })
    attempt(log, "throwing getter", "E-getter", { => w.bad })
    attempt(log, "JSON.parse", "SyntaxError", { => ArkTSRuntime.global().JSON.parse("{") })
    attempt(log, "member of undefined", "", { => w.missing.x })
    attempt(log, "call a number", "", { => w.n() })
    attempt(log, "String from a number", "", { => str(w.n) })
    log.num("usable after errors", num(w.count()))
    var caught = 0.0
    for (_ in 0..100) {
        try {
            w.boom()
        } catch (_: ForeignRuntimeException) {
            caught += 1.0
        }
    }
    log.num("caught in a loop", caught)
    log.num("calls after loop", num(w.count()))
}

func builtins(w: E, log: Transcript): Unit {
    let g = ArkTSRuntime.global()
    let m = g.Reflect.construct(g.Map, to(Array<E>()))
    m.set("a", 1.0)
    m.set(2.0, "two")
    let key = ArkTSRuntime.object()
    m.set(key, true)
    log.num("map size", num(m.size))
    log.num("get a", num(m.get("a")))
    log.str("get 2", str(m.get(2.0)))
    log.bool("get object key", from<Bool>(m.get(key)))
    log.bool("has missing", from<Bool>(m.has("zz")))
    m.delete("a")
    log.num("size after delete", num(m.size))
    log.str("keys", str(g.JSON.stringify(g.Array.from(m.keys()))))
    let s = g.Reflect.construct(g.Set, to(Array<E>()))
    s.add(1.0)
    s.add(1.0)
    s.add("1")
    log.num("set size", num(s.size))
    let o = ArkTSRuntime.object()
    o.name = "n"
    o.list = [1.0, 2.0, 3.0]
    o.nested = ArkTSRuntime.object()
    o.nested.ok = true
    o.nothing = ArkTSRuntime.null()
    log.str("stringify", str(g.JSON.stringify(o)))
    let p = g.JSON.parse("{\"x\":[1,{\"y\":\"z\"}],\"n\":-0.5}")
    log.str("parse y", str(p.x[1].y))
    log.num("parse n", num(p.n))
    log.str("Object.keys", String.join(ArkTSRuntime.objectKeys(p), delimiter: ","))
    log.num("Math.max", num(g.Math.max(1.0, 9.0, 3.0)))
    log.num("Math.hypot", num(g.Math.hypot(3.0, 4.0)))
    log.num("parseInt", num(g.parseInt("ff", 16.0)))
    log.str("String(123.5)", str(g.String(123.5)))
    attempt(log, "toFixed on a number", "", { => to(3.14159).toFixed(2.0) })
    attempt(log, "toUpperCase on a string", "", { => to("abc").toUpperCase() })
    log.text("kind of a symbol", str(w.kind(ArkTSRuntime.symbol(description: "s"))))
}

func longTurn(w: E, log: Transcript): Unit {
    let early = w.t.a
    var sum = 0.0
    for (_ in 0..200000) { sum += num(w.t.a.b) }
    log.num("sum", sum)
    let kept = ArrayList<E>()
    for (i in 0..20000) {
        let o = w.fresh(Float64(i))
        if (i % 1000 == 0) { kept.add(o) }
    }
    log.num("kept", Float64(kept.size))
    var ids = 0.0
    for (o in kept) { ids += num(o.id) }
    log.num("kept ids", ids)
    log.num("early still readable", num(early.b))
    w.t.a.b = 2.0
    log.num("early sees the write", num(early.b))
    log.bool("early identity", same(early, w.t.a))
}

func gcChurn(w: E, log: Transcript): Unit {
    let kept = ArrayList<E>()
    for (round in 0..3) {
        for (i in 0..20000) {
            let o = w.fresh(Float64(round * 20000 + i))
            if (i % 2000 == 0) { kept.add(o) }
            if (i % 5000 == 1) { w.store.push(o) }
        }
        gc(heavy: true)
    }
    var ids = 0.0
    var payloads = 0.0
    for (o in kept) {
        ids += num(o.id)
        payloads += num(o.payload[1])
    }
    log.num("kept", Float64(kept.size))
    log.num("kept ids", ids)
    log.num("kept payloads", payloads)
    log.num("stored", num(w.store.length))
    var stored = 0.0
    for (i in 0..Int64(num(w.store.length))) { stored += num(w.store[i].id) }
    log.num("stored ids", stored)
}

func walk(w: E, x: E): String {
    match (str(w.kind(x))) {
        case "number" => fmtNum(num(x))
        case "string" => fmtStr(str(x))
        case "boolean" => from<Bool>(x).toString()
        case "null" => "null"
        case "array" =>
            let parts = ArrayList<String>()
            for (i in 0..Int64(num(x.length))) { parts.add(walk(w, x[i])) }
            "[" + String.join(parts.toArray(), delimiter: ",") + "]"
        case _ =>
            let keys = ArkTSRuntime.objectKeys(x)
            "{" + String.join(keys.map({ k => fmtStr(k) + ":" + walk(w, x[k]) }), delimiter: ",") + "}"
    }
}

func copyOf(w: E, x: E): E {
    match (str(w.kind(x))) {
        case "array" =>
            let out = to(Array<E>())
            for (i in 0..Int64(num(x.length))) { out.push(copyOf(w, x[i])) }
            out
        case "object" =>
            let out = ArkTSRuntime.object()
            for (k in ArkTSRuntime.objectKeys(x)) { out[k] = copyOf(w, x[k]) }
            out
        case _ => x
    }
}

func jsonWalk(w: E, log: Transcript): Unit {
    log.str("walk", walk(w, w.doc))
    w.copy = copyOf(w, w.doc)
    log.str("copy stringified", str(ArkTSRuntime.global().JSON.stringify(w.copy)))
    log.bool("copy is a new object", same(w.copy, w.doc))
    w.doc.o.a.b[1].added = "yes"
    log.str("walk after edit", walk(w, w.doc.o))
}

func optText<T>(x: ?T, show: (T) -> String): String {
    match (x) {
        case Some(v) => "some:" + show(v)
        case None => "none"
    }
}

func options(w: E, log: Transcript): Unit {
    w.out.a = Some(1.5)
    w.out.b = None<Float64>
    w.out.c = Some("s")
    w.out.d = None<String>
    w.out.e = Some(true)
    w.out.f = None<Bool>
    for (k in ["a", "b", "c", "d", "e", "f"]) { log.text("written ${k}", str(w.kind(w.out[k]))) }
    log.text("?Float64 from undefined", optText(from<?Float64>(w.vals.undef), fmtNum))
    log.text("?Float64 from null", optText(from<?Float64>(w.vals.nul), fmtNum))
    log.text("?Float64 from 2", optText(from<?Float64>(w.vals.two), fmtNum))
    log.text("?String from str", optText(from<?String>(w.vals.s), fmtStr))
    log.text("?Bool from true", optText(from<?Bool>(w.vals.t), { b: Bool => b.toString() }))
    log.text("?String from undefined", optText(from<?String>(w.vals.undef), fmtStr))
    log.text("Array<?Float64> read",
        String.join(from<Array<?Float64>>(w.optArr).map({ x => optText(x, fmtNum) }), delimiter: ","))
    w.out.arr = [Some(1.0), None<Float64>]
    log.str("Array<?Float64> written", str(ArkTSRuntime.global().JSON.stringify(w.out.arr)))
}

let THREADS = 8
let THREAD_ITERATIONS = 200

func manyThreads(w: E, log: Transcript, offThread: Bool): Unit {
    let logs = Array<Transcript>(THREADS) { _ => Transcript() }
    let progress = AtomicInt64(0)
    let interleaved = AtomicBool(false)
    if (offThread) {
        let start = Barrier(THREADS)
        let finished = AtomicBool(false)
        let collector = spawn {
            while (!finished.load()) {
                gc(heavy: true)
                sleep(Duration.millisecond * 2)
            }
        }
        let bodies = Array(THREADS) { t =>
            spawn {
                start.wait()
                threadBody(w, t, logs[t], progress, interleaved)
            }
        }
        for (body in bodies) { body.get() }
        finished.store(true)
        collector.get()
        if (!interleaved.load()) { log.text("concurrent bodies", "not interleaved") }
    } else {
        for (t in 0..THREADS) { threadBody(w, t, logs[t], progress, interleaved) }
    }
    for (threadLog in logs) { log.append(threadLog) }
    log.num("bumps", num(w.shared.bumps))
}

func threadBody(w: E, t: Int64, log: Transcript, progress: AtomicInt64, interleaved: AtomicBool): Unit {
    try {
        var first = 0
        let own = w.slots[t]
        let kept = ArrayList<E>()
        var acc = 0.0
        var caught = 0.0
        var badText = 0.0
        for (i in 0..THREAD_ITERATIONS) {
            let seen = progress.fetchAdd(1)
            if (i == 0) { first = seen }
            if (i == THREAD_ITERATIONS - 1 && seen - first != i) { interleaved.store(true) }
            own.n = Float64(i)
            acc += num(own.n)
            acc += num(w.shared.cfg.a.b)
            acc += num(w.shared.add(Float64(t), Float64(i)))
            w.shared.bump()
            let o = w.fresh(Float64(t * 1000 + i))
            if (i % 50 == 0) { kept.add(o) }
            if (i % 25 == 0) { acc += num(w.apply(fn({ args => to(num(args[0]) + 1.0) }), Float64(i))) }
            if (i % 40 == 0) {
                try {
                    w.boom()
                } catch (_: ForeignRuntimeException) {
                    caught += 1.0
                }
            }
            if (i % 20 == 0) {
                let s = "t${t}-${i}-\u{e9}"
                own.s = s
                if (str(own.s) != s) { badText += 1.0 }
            }
            if (i % 100 == 99) { log.num("t${t} acc at ${i}", acc) }
        }
        var ids = 0.0
        for (o in kept) { ids += num(o.id) }
        log.num("t${t} kept ids", ids)
        log.num("t${t} n", num(own.n))
        log.str("t${t} s", str(own.s))
        log.num("t${t} caught", caught)
        log.num("t${t} bad text", badText)
        log.bool("t${t} own identity", same(own, w.slots[t]))
    } catch (e: Exception) {
        log.text("t${t} uncaught", e.toString())
    }
}
