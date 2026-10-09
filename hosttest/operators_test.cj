// Tests entry/src/main/cangjie/arkts/operators.cj, which run.sh compiles into this binary.
// Expected values are what JS computes for the same expression.

import std.unittest.*
import std.unittest.testmacro.*
import std.math.numeric.BigInt

func num(op: String, l: Float64, r: Float64): Float64 {
    numOf(op, Number(l), Number(r))
}

func numOf(op: String, l: JSOperand, r: JSOperand): Float64 {
    match (applyOperator(op, l, r)) {
        case Number(n) => n
        case _ => throw IllegalStateException("not a number result")
    }
}

func big(op: String, l: Int64, r: Int64): BigInt {
    bigOf(op, BigInt(l), BigInt(r))
}

func bigOf(op: String, l: BigInt, r: BigInt): BigInt {
    match (applyOperator(op, Big(l), Big(r))) {
        case Big(n) => n
        case _ => throw IllegalStateException("not a bigint result")
    }
}

func isNegativeZero(n: Float64): Bool {
    n == 0.0 && 1.0 / n < 0.0
}

func failure(block: () -> Any): String {
    try {
        block()
        "no exception"
    } catch (e: ExternCompoundAssignmentException) {
        e.message
    }
}

@Test
class NumberOperators {
    @TestCase
    func arithmetic(): Unit {
        @Expect(num("+", 1.0, 2.0), 3.0)
        @Expect(num("+", 0.1, 0.2), 0.30000000000000004)
        @Expect(num("-", 5.0, 7.5), -2.5)
        @Expect(num("*", 3.0, 4.0), 12.0)
        @Expect(num("/", 1.0, 0.0), Float64.Inf)
        @Expect(num("/", -1.0, 0.0), -Float64.Inf)
        @Expect(num("/", 1.0, -0.0), -Float64.Inf)
        @Expect(num("/", 0.0, 0.0).isNaN(), true)
    }

    @TestCase
    func remainder(): Unit {
        @Expect(num("%", 5.5, 2.0), 1.5)
        @Expect(num("%", -5.5, 2.0), -1.5)
        @Expect(num("%", 5.5, -2.0), 1.5)
        @Expect(num("%", 5.0, 0.0).isNaN(), true)
        @Expect(num("%", Float64.Inf, 2.0).isNaN(), true)
        @Expect(num("%", 5.0, Float64.Inf), 5.0)
        @Expect(num("%", -5.0, -Float64.Inf), -5.0)
        @Expect(num("%", Float64.NaN, 2.0).isNaN(), true)
        @Expect(num("%", 2.0, Float64.NaN).isNaN(), true)
        @Expect(isNegativeZero(num("%", -4.0, 2.0)), true)
    }

    @TestCase
    func power(): Unit {
        @Expect(num("**", 2.0, 10.0), 1024.0)
        @Expect(num("**", 2.0, 0.5), 1.4142135623730951)
        @Expect(num("**", -8.0, 1.0 / 3.0).isNaN(), true)
        @Expect(num("**", 1.0, Float64.NaN).isNaN(), true)
        @Expect(num("**", -1.0, Float64.Inf).isNaN(), true)
        @Expect(num("**", 1.0, -Float64.Inf).isNaN(), true)
        @Expect(num("**", Float64.NaN, 0.0), 1.0)
        @Expect(num("**", 0.0, -1.0), Float64.Inf)
        @Expect(num("**", -0.0, -1.0), -Float64.Inf)
    }

    @TestCase
    func bitwise(): Unit {
        @Expect(num("&", 5.0, 3.0), 1.0)
        @Expect(num("&", -1.0, 255.0), 255.0)
        @Expect(num("&", 4294967301.0, 7.0), 5.0)
        @Expect(num("&", Float64.NaN, 1.0), 0.0)
        @Expect(num("|", Float64.Inf, 0.0), 0.0)
        @Expect(num("|", 2147483648.0, 0.0), -2147483648.0)
        @Expect(num("|", 3.9, 0.0), 3.0)
        @Expect(num("|", -3.9, 0.0), -3.0)
        @Expect(num("|", -4294967297.0, 0.0), -1.0)
        @Expect(num("^", 5.0, 1.0), 4.0)
    }

    @TestCase
    func shifts(): Unit {
        @Expect(num("<<", 1.0, 31.0), -2147483648.0)
        @Expect(num("<<", 1.0, 32.0), 1.0)
        @Expect(num("<<", 1.0, 33.0), 2.0)
        @Expect(num("<<", 1.0, -1.0), -2147483648.0)
        @Expect(num("<<", 4294967295.0, 1.0), -2.0)
        @Expect(num(">>", -8.0, 1.0), -4.0)
        @Expect(num(">>", -1.0, 31.0), -1.0)
        @Expect(num(">>", 16.0, 33.0), 8.0)
    }

    @TestCase
    func primitiveCoercion(): Unit {
        @Expect(numOf("+", Boolean(true), Number(1.0)), 2.0)
        @Expect(numOf("+", Null, Number(1.0)), 1.0)
        @Expect(numOf("&", Boolean(true), Number(3.0)), 1.0)
        @Expect(numOf("+", Undefined, Number(1.0)).isNaN(), true)
    }

    @TestCase
    func unsupported(): Unit {
        @Expect(failure({ => applyOperator("-", Text("5"), Number(1.0)) }), "Unsupported operand for '-='")
        @Expect(failure({ => applyOperator("+", Number(1.0), Reference) }), "Unsupported operand for '+='")
        @Expect(failure({ => applyOperator("??", Number(1.0), Number(2.0)) }),
            "Unsupported compound assignment operator '??='")
    }
}

@Test
class BigIntOperators {
    @TestCase
    func arithmetic(): Unit {
        @Expect(big("+", 10, 5), BigInt(15))
        @Expect(big("-", 10, 15), BigInt(-5))
        @Expect(big("*", -4, 5), BigInt(-20))
        @Expect(big("/", -7, 2), BigInt(-3))
        @Expect(big("%", -7, 2), BigInt(-1))
        @Expect(big("%", 7, -2), BigInt(1))
        @Expect(big("**", 2, 64), BigInt(1) << 64)
    }

    @TestCase
    func bitwiseAndShifts(): Unit {
        @Expect(big("&", -7, 2), BigInt(0))
        @Expect(big("|", -7, 2), BigInt(-5))
        @Expect(big("^", -7, 2), BigInt(-5))
        @Expect(big("<<", 1, 70), BigInt(1) << 70)
        @Expect(big(">>", -7, 1), BigInt(-4))
        @Expect(big("<<", 8, -2), BigInt(2))
        @Expect(big(">>", 8, -2), BigInt(32))
        let huge = BigInt(1) << 40
        @Expect(bigOf(">>", BigInt(-1), huge), BigInt(-1))
        @Expect(bigOf(">>", BigInt(5), huge), BigInt(0))
    }

    @TestCase
    func errors(): Unit {
        @Expect(failure({ => big("/", 1, 0) }), "BigInt division by zero")
        @Expect(failure({ => big("%", 1, 0) }), "BigInt division by zero")
        @Expect(failure({ => big("**", 2, -1) }), "BigInt negative exponent")
        @Expect(failure({ => bigOf("<<", BigInt(1), BigInt(1) << 40) }), "BigInt '<<=' operand too large")
        @Expect(failure({ => applyOperator("+", Big(BigInt(1)), Number(1.0)) }),
            "Cannot mix BigInt and other types in '+='")
        @Expect(failure({ => applyOperator("+", Number(1.0), Big(BigInt(1))) }),
            "Cannot mix BigInt and other types in '+='")
    }
}

@Test
class Truthiness {
    @TestCase
    func table(): Unit {
        @Expect(isTruthy(Number(0.0)), false)
        @Expect(isTruthy(Number(-0.0)), false)
        @Expect(isTruthy(Number(Float64.NaN)), false)
        @Expect(isTruthy(Number(0.5)), true)
        @Expect(isTruthy(Big(BigInt(0))), false)
        @Expect(isTruthy(Big(BigInt(-1))), true)
        @Expect(isTruthy(Text("")), false)
        @Expect(isTruthy(Text("0")), true)
        @Expect(isTruthy(Boolean(false)), false)
        @Expect(isTruthy(Undefined), false)
        @Expect(isTruthy(Null), false)
        @Expect(isTruthy(Reference), true)
    }
}
