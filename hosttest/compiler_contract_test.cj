import std.unittest.*
import std.unittest.testmacro.*

type R = RecordingRuntime

func logged(): String {
    var out = ""
    for (i in 0..R.log.size) {
        if (i > 0) { out += "\n" }
        out += R.log[i]
    }
    out
}

func lines(items: Array<String>): String {
    var out = ""
    for (i in 0..items.size) {
        if (i > 0) { out += "\n" }
        out += items[i]
    }
    out
}

func sideEffect(): Int64 {
    R.log.add("side")
    1
}

func acceptExtern(_: Extern<R>): Unit {}

func plainCangjie(value: Extern<R>): Int64 {
    R.log.add("plainCangjie ${R.render(value)}")
    7
}

@Test
class MemberAccessContract {
    @BeforeEach
    func setUp(): Unit { R.reset() }

    @TestCase
    func singleMember(): Unit {
        let e = R.named("e")
        let _ = e.f
        @Expect(logged(), lines(["memberAccess(e, f)"]))
    }

    @TestCase
    func chainIsOneCallPerMember(): Unit {
        let e = R.named("e")
        let _ = e.a.b.c
        @Expect(logged(), lines(["memberAccess(e, a)", "memberAccess(r1, b)", "memberAccess(r2, c)"]))
    }
}

@Test
class CallContract {
    @BeforeEach
    func setUp(): Unit { R.reset() }

    @TestCase
    func methodCallIsMemberAccessThenCallWithRawLeaves(): Unit {
        let e = R.named("e")
        let _ = e.m(1, "s", 2.5)
        @Expect(logged(), lines(["memberAccess(e, m)", "functionCall(r1, [1:Int64, \"s\":String, 2.500000:Float64])"]))
    }

    @TestCase
    func callThroughStoredFunctionIsTheSameCall(): Unit {
        let e = R.named("e")
        let x = e.m
        let _ = x(1)
        @Expect(logged(), lines(["memberAccess(e, m)", "functionCall(r1, [1:Int64])"]))
    }

    @TestCase
    func externArgumentIsEvaluatedAfterCallee(): Unit {
        let e = R.named("e")
        let _ = e.f(e.g)
        @Expect(logged(), lines(["memberAccess(e, f)", "memberAccess(e, g)", "functionCall(r1, [r2])"]))
    }

    @TestCase
    func callThroughIndex(): Unit {
        let e = R.named("e")
        let _ = e.methods[0](1)
        @Expect(logged(), lines(["memberAccess(e, methods)", "indexedAccess(r1, 0:Int64)", "functionCall(r2, [1:Int64])"]))
    }

    @TestCase
    func callResultCalledAgain(): Unit {
        let e = R.named("e")
        let _ = e.f(1)(2)
        @Expect(logged(), lines(["memberAccess(e, f)", "functionCall(r1, [1:Int64])", "functionCall(r2, [2:Int64])"]))
    }

    @TestCase
    func binaryOperatorIsMethodCall(): Unit {
        let e = R.named("e")
        let _ = e + 1
        @Expect(logged(), lines(["memberAccess(e, +)", "functionCall(r1, [1:Int64])"]))
    }

    @TestCase
    func plainCangjieCallEvaluatesExternArgumentFirst(): Unit {
        let e = R.named("e")
        let _ = plainCangjie(e.a)
        @Expect(logged(), lines(["memberAccess(e, a)", "plainCangjie r1"]))
    }
}

@Test
class IndexContract {
    @BeforeEach
    func setUp(): Unit { R.reset() }

    @TestCase
    func integerIndex(): Unit {
        let e = R.named("e")
        let _ = e[0]
        @Expect(logged(), lines(["indexedAccess(e, 0:Int64)"]))
    }

    @TestCase
    func stringIndex(): Unit {
        let e = R.named("e")
        let _ = e["k"]
        @Expect(logged(), lines(["indexedAccess(e, \"k\":String)"]))
    }

    @TestCase
    func externIndexIsEvaluatedFirst(): Unit {
        let e = R.named("e")
        let _ = e[e.k]
        @Expect(logged(), lines(["memberAccess(e, k)", "indexedAccess(e, r1)"]))
    }
}

@Test
class UpdateContract {
    @BeforeEach
    func setUp(): Unit { R.reset() }

    @TestCase
    func memberUpdate(): Unit {
        let e = R.named("e")
        e.f = 1
        @Expect(logged(), lines(["memberUpdate(e, f, 1:Int64)"]))
    }

    @TestCase
    func indexedUpdate(): Unit {
        let e = R.named("e")
        e[0] = 1
        @Expect(logged(), lines(["indexedUpdate(e, 0:Int64, 1:Int64)"]))
    }

    @TestCase
    func nestedUpdateFromDesign(): Unit {
        let a = R.named("a")
        let d = R.named("d")
        a.b(42).c = d.e().f()
        @Expect(logged(), lines([
            "memberAccess(a, b)",
            "functionCall(r1, [42:Int64])",
            "memberAccess(d, e)",
            "functionCall(r3, [])",
            "memberAccess(r4, f)",
            "functionCall(r5, [])",
            "memberUpdate(r2, c, r6)"
        ]))
    }

    @TestCase
    func memberCompoundAssignment(): Unit {
        let e = R.named("e")
        e.f += 1
        @Expect(logged(), lines([
            "memberAccess(e, f)",
            "memberAccess(r1, +)",
            "functionCall(r2, [1:Int64])",
            "memberUpdate(e, f, r3)"
        ]))
    }

    @TestCase
    func indexedCompoundAssignment(): Unit {
        let e = R.named("e")
        e[0] += 1
        @Expect(logged(), lines([
            "indexedAccess(e, 0:Int64)",
            "memberAccess(r1, +)",
            "functionCall(r2, [1:Int64])",
            "indexedUpdate(e, 0:Int64, r3)"
        ]))
    }

    @TestCase
    func variableCompoundAssignmentIsMethodCall(): Unit {
        var x = R.named("x")
        x += 1
        @Expect(logged(), lines(["memberAccess(x, +)", "functionCall(r1, [1:Int64])"]))
        @Expect(R.render(x), "r2")
    }
}

@Test
class ConversionContract {
    @BeforeEach
    func setUp(): Unit { R.reset() }

    @TestCase
    func implicitConversionOfInitializer(): Unit {
        let v: Extern<R> = 42
        @Expect(logged(), lines(["toExtern 42:Int64"]))
        @Expect(R.render(v), "t(42:Int64)")
    }

    @TestCase
    func implicitConversionOfAssignmentAndArgument(): Unit {
        var v: Extern<R> = R.named("v")
        v = 1
        acceptExtern(2)
        @Expect(logged(), lines(["toExtern 1:Int64", "toExtern 2:Int64"]))
    }

    @TestCase
    func wildcardBindingConverts(): Unit {
        let _: Extern<R> = sideEffect()
        @Expect(logged(), lines(["side", "toExtern 1:Int64"]))
    }

    @TestCase
    func implicitConversionPerArrayElement(): Unit {
        let _: Array<Extern<R>> = [1, "a"]
        @Expect(logged(), lines(["toExtern 1:Int64", "toExtern \"a\":String"]))
    }

    @TestCase
    func implicitConversionOfWholeArray(): Unit {
        let v: Extern<R> = [1, 2]
        @Expect(logged(), lines(["toExtern [1:Int64, 2:Int64]:Array<Int64>"]))
        @Expect(R.render(v), "t([1:Int64, 2:Int64]:Array<Int64>)")
    }

    @TestCase
    func explicitFromExternReceivesEvaluatedValue(): Unit {
        let e = R.named("e")
        let _ = R.fromExtern<Float64>(e.a.b)
        @Expect(logged(), lines(["memberAccess(e, a)", "memberAccess(r1, b)", "fromExtern r2"]))
    }
}
