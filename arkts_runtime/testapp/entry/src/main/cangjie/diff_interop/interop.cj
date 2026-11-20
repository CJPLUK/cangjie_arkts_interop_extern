package ohos_app_cangjie_entry.diff_interop

import std.collection.ArrayList
import std.runtime.gc
import ohos.ark_interop.*
import ohos_app_cangjie_entry.difflog.*

class Js {
    Js(let c: JSContext) {}

    func n(x: Float64): JSValue { c.number(x).toJSValue() }
    func s(x: String): JSValue { c.string(x).toJSValue() }
    func b(x: Bool): JSValue { c.boolean(x).toJSValue() }
    func undef(): JSValue { c.undefined().toJSValue() }
    func null(): JSValue { c.null().toJSValue() }
    func obj(): JSValue { c.object().toJSValue() }
    func arr(elements: Array<JSValue>): JSValue { c.array(elements).toJSValue() }
    func fn(body: (Array<JSValue>) -> JSValue): JSValue {
        c.function({ _, info => body(Array<JSValue>(info.count) { i => info[i] }) }).toJSValue()
    }
    func global(): JSValue { c.global.toJSValue() }
}

func get(o: JSValue, k: String): JSValue { o.getProperty(k) }

func set(o: JSValue, k: String, v: JSValue): Unit { o.setProperty(k, v) }

func at(o: JSValue, i: Int64): JSValue { o.getElement(i) }

func put(o: JSValue, i: Int64, v: JSValue): Unit { o.setElement(i, v) }

func call(recv: JSValue, name: String, args: Array<JSValue>): JSValue {
    recv.getProperty(name).asFunction().call(args, thisArg: recv)
}

func num(x: JSValue): Float64 { x.toNumber() }

func str(x: JSValue): String { x.toString() }

func keys(o: JSValue): String { String.join(o.asObject().keys(), delimiter: ",") }

func length(o: JSValue): Int64 { Int64(num(get(o, "length"))) }

func attempt(log: Transcript, label: String, fragment: String, body: () -> Any): Unit {
    let outcome = try {
        body()
        "ok"
    } catch (e: Exception) {
        "js:${e.toString().contains(fragment)}"
    }
    log.text(label, outcome)
}

/** Whether `s` holds valid UTF-8: a String read from a lone surrogate does not, and iterating it throws. */
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

public func runProgram(context: JSContext, name: String, world: JSValue): String {
    let log = Transcript()
    let js = Js(context)
    try {
        match (name) {
            case "objectGraph" => objectGraph(js, world, log)
            case "internChurn" => internChurn(js, world, log)
            case "numbers" => numbers(js, world, log)
            case "strings" => strings(js, world, log)
            case "arrays" => arrays(js, world, log)
            case "methodsAndThis" => methodsAndThis(js, world, log)
            case "callbacks" => callbacks(js, world, log)
            case "exceptions" => exceptions(js, world, log)
            case "builtins" => builtins(js, world, log)
            case "longTurn" => longTurn(js, world, log)
            case "gcChurn" => gcChurn(js, world, log)
            case "jsonWalk" => jsonWalk(js, world, log)
            case "options" => options(js, world, log)
            case "manyThreads" => manyThreads(js, world, log)
            case _ => log.text("unknown program", name)
        }
    } catch (e: Exception) {
        log.text("uncaught", e.toString())
    }
    log.render()
}

func objectGraph(js: Js, w: JSValue, log: Transcript): Unit {
    let r = get(w, "root")
    let d = { => get(get(get(get(r, "a"), "b"), "c"), "d") }
    log.num("d", num(d()))
    set(get(get(get(r, "a"), "b"), "c"), "d", js.n(2.5))
    log.num("d after write", num(d()))
    log.bool("a read twice is one object", get(r, "a").strictEqual(get(r, "a")))
    let oldB = get(get(r, "a"), "b")
    let nb = js.obj()
    set(nb, "c", js.obj())
    set(get(nb, "c"), "d", js.n(7.0))
    set(get(r, "a"), "b", nb)
    log.num("d via new b", num(d()))
    log.bool("b replaced", oldB.strictEqual(get(get(r, "a"), "b")))
    log.num("old b still readable", num(get(get(oldB, "c"), "d")))
    let a = get(r, "a")
    set(r, "a", get(r, "x"))
    set(r, "x", a)
    log.str("a.tag after swap", str(get(get(r, "a"), "tag")))
    log.num("x.b.c.d after swap", num(get(get(get(get(r, "x"), "b"), "c"), "d")))
    set(r, "self", r)
    log.bool("cycle", get(get(get(r, "self"), "self"), "self").strictEqual(r))
    set(r, "x", js.undef())
    log.bool("x undefined", get(r, "x").isUndefined())
    log.text("keys", keys(r))
}

func internChurn(js: Js, w: JSValue, log: Transcript): Unit {
    let slot = { => get(get(w, "holder"), "slot") }
    let child = { k: Int64 => get(at(get(w, "many"), k), "child") }
    var sum = 0.0
    var wrongId = 0.0
    var sameAsBefore = 0.0
    for (i in 1..=300) {
        let before = slot()
        call(w, "rotate", [js.n(Float64(i))])
        let after = slot()
        if (num(get(after, "id")) != Float64(i)) { wrongId += 1.0 }
        if (before.strictEqual(after)) { sameAsBefore += 1.0 }
        sum += num(get(after, "id"))
    }
    log.num("sum", sum)
    log.num("wrong ids", wrongId)
    log.num("same as before", sameAsBefore)
    var total = 0.0
    for (_ in 0..3) {
        for (k in 0..600) { total += num(get(child(k), "v")) }
    }
    log.num("many total", total)
    let first = child(0)
    call(w, "mutateMany", [])
    total = 0.0
    for (k in 0..600) { total += num(get(child(k), "v")) }
    log.num("many total after JS mutation", total)
    log.bool("replaced child differs", first.strictEqual(child(0)))
    let kept = child(0)
    for (k in 0..600) { total += num(get(child(k), "v")) }
    log.bool("identity after 600 other receivers", kept.strictEqual(child(0)))
    log.bool("different receivers differ", child(1).strictEqual(child(2)))
    set(get(w, "holder"), "slot", child(5))
    log.bool("slot set from another read", slot().strictEqual(child(5)))
    set(get(w, "holder"), "slot", js.n(3.0))
    log.num("slot as number", num(slot()))
    set(get(w, "holder"), "slot", child(7))
    log.num("slot back to object", num(get(slot(), "v")))
    set(child(7), "v", js.n(-1.0))
    log.num("write through other path", num(get(slot(), "v")))
}

func isInt32(x: Float64): Bool {
    !x.isNaN() && x >= -2147483648.0 && x <= 2147483647.0 && x == Float64(Int64(x))
}

func numbers(js: Js, w: JSValue, log: Transcript): Unit {
    let vals = get(w, "vals")
    let out = get(w, "out")
    for (i in 0..length(vals)) {
        let x = num(at(vals, i))
        log.num("v${i}", x)
        let y = x * 3.0 + 1.0
        set(out, "v", js.n(y))
        log.num("v${i} written", num(get(out, "v")))
        log.num("v${i} echo", num(call(w, "echo", [js.n(y)])))
        log.text("v${i} Int32", if (isInt32(x)) { Int32(x).toString() } else { "conversion" })
        log.num("v${i} Float32", Float64(Float32(x)))
    }
    set(out, "big", js.c.bigint(9007199254740993).toJSValue())
    log.text("Int64 written kind", str(call(w, "kind", [get(out, "big")])))
    log.text("Int64 read", get(out, "big").toBigInt().toString())
    set(out, "min", js.c.bigint(Int64.Min).toJSValue())
    log.text("Int64.Min read", get(out, "min").toBigInt().toString())
    log.text("Int64 from a number", if (at(vals, 0).isBigInt()) { "ok" } else { "conversion" })
    set(out, "i32", js.n(Float64(Int32.Max)))
    log.text("Int32 written kind", str(call(w, "kind", [get(out, "i32")])))
    log.num("sum", num(call(w, "sum", [js.n(0.1), js.n(0.2)])))
    log.num("sum of extremes", num(call(w, "sum", [at(vals, 7), at(vals, 7)])))
}

func strings(js: Js, w: JSValue, log: Transcript): Unit {
    let strs = get(w, "strs")
    let out = get(w, "out")
    for (i in 0..length(strs)) {
        let s = str(at(strs, i))
        if (!wellFormed(s)) {
            log.text("s${i}", "malformed")
            continue
        }
        log.str("s${i}", s)
        log.num("s${i} js length", num(call(w, "len", [at(strs, i)])))
        let t = s + "|" + s
        set(out, "s", js.s(t))
        log.num("s${i} written length", num(call(w, "len", [get(out, "s")])))
        log.str("s${i} echo", str(call(w, "echo", [js.s(t)])))
        log.bool("s${i} round trip", str(get(out, "s")) == t)
    }
    log.text("member read on a string", if (at(strs, 1).isObject()) { "ok" } else { "member" })
    set(out, "kéy", js.n(1.0))
    set(out, "", js.n(2.0))
    log.text("keys", String.join(out.asObject().keys().map({ k => fmtStr(k) }), delimiter: ","))
    log.num("index by unicode key", num(get(out, "kéy")))
}

func arrays(js: Js, w: JSValue, log: Transcript): Unit {
    let a = get(w, "arr")
    let kind = { x: JSValue => str(call(w, "kind", [x])) }
    log.num("length", Float64(length(a)))
    for (i in 0..7) { log.text("kind ${i}", kind(at(a, i))) }
    log.text("out of bounds", if (100 < length(a)) { "ok" } else { "index" })
    put(a, 10, js.s("far"))
    log.num("length after far write", Float64(length(a)))
    log.text("hole", kind(at(a, 8)))
    set(a, "length", js.n(3.0))
    log.num("length after shrink", Float64(length(a)))
    log.text("element past shrink", if (5 < length(a)) { "ok" } else { "index" })
    log.num("push", num(call(a, "push", [js.n(42.0)])))
    log.num("indexOf", num(call(a, "indexOf", [js.n(42.0)])))
    log.str("Float64 index", str(at(a, 1)))
    log.bool("String index", get(a, "2").toBoolean())
    let nested = get(w, "nested")
    log.num("nested", num(at(at(at(nested, 1), 1), 0)))
    put(at(at(nested, 1), 1), 1, js.n(50.0))
    log.num("nested write", num(at(at(at(nested, 1), 1), 1)))
    let json = get(js.global(), "JSON")
    let out = get(w, "out")
    set(out, "floats", js.arr([js.n(1.5), js.n(2.5)]))
    log.str("Array<Float64> written", str(call(json, "stringify", [get(out, "floats")])))
    set(out, "strs", js.arr([js.s("x"), js.s("y")]))
    log.str("Array<String> written", str(call(json, "stringify", [get(out, "strs")])))
    set(out, "opts", js.arr([js.n(1.0), js.undef()]))
    log.str("Array<?Float64> written", str(call(json, "stringify", [get(out, "opts")])))
    set(out, "nested", js.arr([js.arr([js.n(1.0), js.n(2.0)]), js.arr([js.n(3.0)])]))
    log.str("Array<Array<Float64>> written", str(call(json, "stringify", [get(out, "nested")])))
    let nums = get(w, "nums")
    var total = 0.0
    for (i in 0..length(nums)) { total += num(at(nums, i)) }
    log.num("Array<Float64> read sum", total)
    call(nums, "sort", [])
    log.str("default sort", str(call(nums, "join", [js.s(",")])))
    call(nums, "reverse", [])
    log.str("reverse", str(call(nums, "join", [js.s(",")])))
    log.num("Array.isArray", if (nums.isArray()) { 1.0 } else { 0.0 })
}

func methodsAndThis(js: Js, w: JSValue, log: Transcript): Unit {
    let c = get(w, "c")
    log.num("inc 2", num(call(c, "inc", [js.n(2.0)])))
    log.num("inc 3", num(call(c, "inc", [js.n(3.0)])))
    log.num("getter", num(get(c, "double")))
    set(c, "value", js.n(4.0))
    log.num("after setter", num(get(c, "count")))
    let inc = get(c, "inc").asFunction()
    log.num("extracted method keeps this", num(inc.call([js.n(1.0)], thisArg: c)))
    log.num("static", num(call(call(get(w, "Counter"), "make", []), "inc", [js.n(5.0)])))
    log.text("method this", str(call(w, "whoAmI", [])))
    let who = get(w, "whoAmI").asFunction()
    log.text("extracted function this", str(who.call(thisArg: w)))
    log.num("index call", num(call(c, "inc", [js.n(1.0)])))
    let c2 = call(get(js.global(), "Reflect"), "construct", [get(w, "Counter"), js.arr([])])
    log.num("Reflect.construct", num(call(c2, "inc", [js.n(7.0)])))
    log.bool("shared prototype method", get(c, "inc").strictEqual(get(c2, "inc")))
    log.bool("instances differ", c.strictEqual(c2))
    let next = call(w, "makeCounter", []).asFunction()
    next.call()
    next.call()
    log.num("closure", num(next.call()))
    log.text("own keys", keys(c))
}

func callbacks(js: Js, w: JSValue, log: Transcript): Unit {
    let nums = get(w, "nums")
    log.num("apply", num(call(w, "apply", [js.fn({ args => js.n(num(args[0]) * num(args[0])) }), js.n(7.0)])))
    log.num("twice", num(call(w, "twice", [js.fn({ args => js.n(num(args[0]) + 10.0) })])))
    let mapped = call(nums, "map", [js.fn({ args => js.n(num(args[0]) * 10.0) })])
    log.str("map", str(call(mapped, "join", [js.s(",")])))
    let sorted = call(call(nums, "slice", []), "sort", [js.fn({ args => js.n(num(args[0]) - num(args[1])) })])
    log.str("sort", str(call(sorted, "join", [js.s(",")])))
    log.num("reenter", num(call(w, "reenter", [js.fn({ args => js.n(num(call(w, "inner", [args[0]])) + 5.0) })])))
    log.str("callback throws", str(call(w, "callAndCatch", [js.fn({ _ => throw Exception("cbBoom") })])))
    log.str("callback returns string",
        str(call(w, "apply", [js.fn({ args => js.s(str(args[0]) + "!") }), js.s("hi")])))
    log.text("callback returns undefined",
        str(call(w, "kind", [call(w, "apply", [js.fn({ _ => js.undef() }), js.n(0.0)])])))
    let count = Cell()
    call(nums, "forEach", [js.fn({ _ =>
        count.value += 1.0
        js.undef()
    })])
    log.num("forEach count", count.value)
    call(w, "apply", [js.fn({ args =>
        set(args[0], "touched", js.b(true))
        args[0]
    }), get(w, "target")])
    log.bool("callback mutated its argument", get(get(w, "target"), "touched").toBoolean())
    log.num("reduce over 5000",
        num(call(get(w, "range"), "reduce", [js.fn({ args => js.n(num(args[0]) + num(args[1])) }), js.n(0.0)])))
    let seen = Cell()
    let f = js.fn({ args =>
        seen.value += num(args[0])
        js.n(seen.value)
    })
    call(w, "apply", [f, js.n(1.0)])
    call(w, "apply", [f, js.n(2.0)])
    log.num("one function called twice", num(call(w, "apply", [f, js.n(3.0)])))
}

func exceptions(js: Js, w: JSValue, log: Transcript): Unit {
    attempt(log, "Error", "E-boom", { => call(w, "boom", []) })
    attempt(log, "thrown string", "E-str", { => call(w, "throwStr", []) })
    attempt(log, "throwing getter", "E-getter", { => get(w, "bad") })
    attempt(log, "JSON.parse", "SyntaxError", { => call(get(js.global(), "JSON"), "parse", [js.s("{")]) })
    log.text("member of undefined", if (get(w, "missing").isObject()) { "ok" } else { "member" })
    log.text("call a number", if (get(w, "n").isFunction()) { "ok" } else { "function" })
    log.text("String from a number", if (get(w, "n").isString()) { "ok" } else { "conversion" })
    log.num("usable after errors", num(call(w, "count", [])))
    var caught = 0.0
    for (_ in 0..100) {
        try {
            call(w, "boom", [])
        } catch (_: Exception) {
            caught += 1.0
        }
    }
    log.num("caught in a loop", caught)
    log.num("calls after loop", num(call(w, "count", [])))
}

func builtins(js: Js, w: JSValue, log: Transcript): Unit {
    let g = js.global()
    let reflect = get(g, "Reflect")
    let m = call(reflect, "construct", [get(g, "Map"), js.arr([])])
    call(m, "set", [js.s("a"), js.n(1.0)])
    call(m, "set", [js.n(2.0), js.s("two")])
    let key = js.obj()
    call(m, "set", [key, js.b(true)])
    log.num("map size", num(get(m, "size")))
    log.num("get a", num(call(m, "get", [js.s("a")])))
    log.str("get 2", str(call(m, "get", [js.n(2.0)])))
    log.bool("get object key", call(m, "get", [key]).toBoolean())
    log.bool("has missing", call(m, "has", [js.s("zz")]).toBoolean())
    call(m, "delete", [js.s("a")])
    log.num("size after delete", num(get(m, "size")))
    let json = get(g, "JSON")
    log.str("keys", str(call(json, "stringify", [call(get(g, "Array"), "from", [call(m, "keys", [])])])))
    let s = call(reflect, "construct", [get(g, "Set"), js.arr([])])
    call(s, "add", [js.n(1.0)])
    call(s, "add", [js.n(1.0)])
    call(s, "add", [js.s("1")])
    log.num("set size", num(get(s, "size")))
    let o = js.obj()
    set(o, "name", js.s("n"))
    set(o, "list", js.arr([js.n(1.0), js.n(2.0), js.n(3.0)]))
    set(o, "nested", js.obj())
    set(get(o, "nested"), "ok", js.b(true))
    set(o, "nothing", js.null())
    log.str("stringify", str(call(json, "stringify", [o])))
    let p = call(json, "parse", [js.s("{\"x\":[1,{\"y\":\"z\"}],\"n\":-0.5}")])
    log.str("parse y", str(get(at(get(p, "x"), 1), "y")))
    log.num("parse n", num(get(p, "n")))
    log.str("Object.keys", keys(p))
    let math = get(g, "Math")
    log.num("Math.max", num(call(math, "max", [js.n(1.0), js.n(9.0), js.n(3.0)])))
    log.num("Math.hypot", num(call(math, "hypot", [js.n(3.0), js.n(4.0)])))
    log.num("parseInt", num(call(g, "parseInt", [js.s("ff"), js.n(16.0)])))
    log.str("String(123.5)", str(call(g, "String", [js.n(123.5)])))
    log.text("toFixed on a number", if (js.n(3.14159).isObject()) { "ok" } else { "member" })
    log.text("toUpperCase on a string", if (js.s("abc").isObject()) { "ok" } else { "member" })
    log.text("kind of a symbol", str(call(w, "kind", [js.c.symbol(description: "s").toJSValue(js.c)])))
}

func longTurn(js: Js, w: JSValue, log: Transcript): Unit {
    let t = get(w, "t")
    let early = get(t, "a")
    var sum = 0.0
    for (_ in 0..200000) { sum += num(get(get(t, "a"), "b")) }
    log.num("sum", sum)
    let kept = ArrayList<JSValue>()
    let fresh = get(w, "fresh").asFunction()
    for (i in 0..20000) {
        let o = fresh.call(js.n(Float64(i)), thisArg: w)
        if (i % 1000 == 0) { kept.add(o) }
    }
    log.num("kept", Float64(kept.size))
    var ids = 0.0
    for (o in kept) { ids += num(get(o, "id")) }
    log.num("kept ids", ids)
    log.num("early still readable", num(get(early, "b")))
    set(get(t, "a"), "b", js.n(2.0))
    log.num("early sees the write", num(get(early, "b")))
    log.bool("early identity", early.strictEqual(get(t, "a")))
}

func gcChurn(js: Js, w: JSValue, log: Transcript): Unit {
    let kept = ArrayList<JSValue>()
    let store = get(w, "store")
    for (round in 0..3) {
        for (i in 0..20000) {
            let o = call(w, "fresh", [js.n(Float64(round * 20000 + i))])
            if (i % 2000 == 0) { kept.add(o) }
            if (i % 5000 == 1) { call(store, "push", [o]) }
        }
        gc(heavy: true)
    }
    var ids = 0.0
    var payloads = 0.0
    for (o in kept) {
        ids += num(get(o, "id"))
        payloads += num(at(get(o, "payload"), 1))
    }
    log.num("kept", Float64(kept.size))
    log.num("kept ids", ids)
    log.num("kept payloads", payloads)
    log.num("stored", Float64(length(store)))
    var stored = 0.0
    for (i in 0..length(store)) { stored += num(get(at(store, i), "id")) }
    log.num("stored ids", stored)
}

func walk(w: JSValue, x: JSValue): String {
    match (str(call(w, "kind", [x]))) {
        case "number" => fmtNum(num(x))
        case "string" => fmtStr(str(x))
        case "boolean" => x.toBoolean().toString()
        case "null" => "null"
        case "array" =>
            let parts = ArrayList<String>()
            for (i in 0..length(x)) { parts.add(walk(w, at(x, i))) }
            "[" + String.join(parts.toArray(), delimiter: ",") + "]"
        case _ =>
            let names = x.asObject().keys()
            "{" + String.join(names.map({ k => fmtStr(k) + ":" + walk(w, get(x, k)) }), delimiter: ",") + "}"
    }
}

func copyOf(js: Js, w: JSValue, x: JSValue): JSValue {
    match (str(call(w, "kind", [x]))) {
        case "array" => js.arr(Array<JSValue>(length(x)) { i => copyOf(js, w, at(x, i)) })
        case "object" =>
            let out = js.obj()
            for (k in x.asObject().keys()) { set(out, k, copyOf(js, w, get(x, k))) }
            out
        case _ => x
    }
}

func jsonWalk(js: Js, w: JSValue, log: Transcript): Unit {
    log.str("walk", walk(w, get(w, "doc")))
    set(w, "copy", copyOf(js, w, get(w, "doc")))
    log.str("copy stringified", str(call(get(js.global(), "JSON"), "stringify", [get(w, "copy")])))
    log.bool("copy is a new object", get(w, "copy").strictEqual(get(w, "doc")))
    set(at(get(get(get(get(w, "doc"), "o"), "a"), "b"), 1), "added", js.s("yes"))
    log.str("walk after edit", walk(w, get(get(w, "doc"), "o")))
}

func options(js: Js, w: JSValue, log: Transcript): Unit {
    let out = get(w, "out")
    set(out, "a", js.n(1.5))
    set(out, "b", js.undef())
    set(out, "c", js.s("s"))
    set(out, "d", js.undef())
    set(out, "e", js.b(true))
    set(out, "f", js.undef())
    for (k in ["a", "b", "c", "d", "e", "f"]) { log.text("written ${k}", str(call(w, "kind", [get(out, k)]))) }
    let none = { x: JSValue => x.isUndefined() || x.isNull() }
    let optNum = { x: JSValue => if (none(x)) { "none" } else { "some:" + fmtNum(num(x)) } }
    let vals = get(w, "vals")
    log.text("?Float64 from undefined", optNum(get(vals, "undef")))
    log.text("?Float64 from null", optNum(get(vals, "nul")))
    log.text("?Float64 from 2", optNum(get(vals, "two")))
    log.text("?String from str", if (none(get(vals, "s"))) { "none" } else { "some:" + fmtStr(str(get(vals, "s"))) })
    log.text("?Bool from true", if (none(get(vals, "t"))) { "none" } else { "some:${get(vals, "t").toBoolean()}" })
    log.text("?String from undefined", if (none(get(vals, "undef"))) { "none" } else { "some" })
    let optArr = get(w, "optArr")
    log.text("Array<?Float64> read",
        String.join(Array<String>(length(optArr)) { i => optNum(at(optArr, i)) }, delimiter: ","))
    set(out, "arr", js.arr([js.n(1.0), js.undef()]))
    log.str("Array<?Float64> written", str(call(get(js.global(), "JSON"), "stringify", [get(out, "arr")])))
}

let THREADS = 8
let THREAD_ITERATIONS = 200

/** DiffPrograms.ts's manyThreads: ark_interop runs only on the JS thread, so the bodies run one after another. */
func manyThreads(js: Js, w: JSValue, log: Transcript): Unit {
    for (t in 0..THREADS) { threadBody(js, w, t, log) }
    log.num("bumps", num(get(get(w, "shared"), "bumps")))
}

func threadBody(js: Js, w: JSValue, t: Int64, log: Transcript): Unit {
    let own = at(get(w, "slots"), t)
    let shared = get(w, "shared")
    let kept = ArrayList<JSValue>()
    var acc = 0.0
    var caught = 0.0
    var badText = 0.0
    for (i in 0..THREAD_ITERATIONS) {
        set(own, "n", js.n(Float64(i)))
        acc += num(get(own, "n"))
        acc += num(get(get(get(shared, "cfg"), "a"), "b"))
        acc += num(call(shared, "add", [js.n(Float64(t)), js.n(Float64(i))]))
        call(shared, "bump", [])
        let o = call(w, "fresh", [js.n(Float64(t * 1000 + i))])
        if (i % 50 == 0) { kept.add(o) }
        if (i % 25 == 0) { acc += num(call(w, "apply", [js.fn({ args => js.n(num(args[0]) + 1.0) }), js.n(Float64(i))])) }
        if (i % 40 == 0) {
            try {
                call(w, "boom", [])
            } catch (_: Exception) {
                caught += 1.0
            }
        }
        if (i % 20 == 0) {
            let s = "t${t}-${i}-\u{e9}"
            set(own, "s", js.s(s))
            if (str(get(own, "s")) != s) { badText += 1.0 }
        }
        if (i % 100 == 99) { log.num("t${t} acc at ${i}", acc) }
    }
    var ids = 0.0
    for (o in kept) { ids += num(get(o, "id")) }
    log.num("t${t} kept ids", ids)
    log.num("t${t} n", num(get(own, "n")))
    log.str("t${t} s", str(get(own, "s")))
    log.num("t${t} caught", caught)
    log.num("t${t} bad text", badText)
    log.bool("t${t} own identity", own.strictEqual(at(get(w, "slots"), t)))
}
