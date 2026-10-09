package ohos_app_cangjie_entry.arkts

// Pure compound-assignment arithmetic with JS semantics. No ohos imports: hosttest/run.sh
// compiles this file on the Mac.

import std.math.fmod
import std.math.trunc
import std.math.numeric.BigInt

/** A JS value as seen by compound-assignment arithmetic. */
enum JSOperand {
    | Number(Float64)
    | Big(BigInt)
    | Boolean(Bool)
    | Text(String)
    | Undefined
    | Null
    | Reference // object, array, function, symbol
}

/** JS ToBoolean. */
func isTruthy(value: JSOperand): Bool {
    match (value) {
        case Number(n) => !(n == 0.0 || n.isNaN())
        case Big(n) => n != BigInt(0)
        case Boolean(b) => b
        case Text(s) => !s.isEmpty()
        case Undefined | Null => false
        case Reference => true
    }
}

/**
 * `left op right` with JS semantics, for `op` in `+ - * / % ** & | ^ << >>` and operands that
 * are not strings (string `+` needs the engine's number formatting). Throws
 * `ExternCompoundAssignmentException` where JS throws (mixing bigint with other types, bigint
 * division by zero or negative exponent) and for unsupported operands or operators.
 */
func applyOperator(op: String, left: JSOperand, right: JSOperand): JSOperand {
    match ((left, right)) {
        case (Big(l), Big(r)) => Big(bigIntOperator(op, l, r))
        case (Big(_), _) | (_, Big(_)) => throw ExternCompoundAssignmentException(
            "Cannot mix BigInt and other types in '${op}='")
        case _ => Number(numberOperator(op, toNumber(op, left), toNumber(op, right)))
    }
}

/** JS ToNumber for the primitives compound assignment accepts. */
func toNumber(op: String, value: JSOperand): Float64 {
    match (value) {
        case Number(n) => n
        case Boolean(b) => if (b) { 1.0 } else { 0.0 }
        case Undefined => Float64.NaN
        case Null => 0.0
        case _ => throw ExternCompoundAssignmentException("Unsupported operand for '${op}='")
    }
}

func numberOperator(op: String, l: Float64, r: Float64): Float64 {
    match (op) {
        case "+" => l + r
        case "-" => l - r
        case "*" => l * r
        case "/" => l / r
        case "%" => remainder(l, r)
        case "**" => power(l, r)
        case "&" => Float64(toInt32(l) & toInt32(r))
        case "|" => Float64(toInt32(l) | toInt32(r))
        case "^" => Float64(toInt32(l) ^ toInt32(r))
        case "<<" => Float64(wrapInt32(Int64(toInt32(l)) << shiftCount(r)))
        case ">>" => Float64(toInt32(l) >> shiftCount(r))
        case _ => throw ExternCompoundAssignmentException("Unsupported compound assignment operator '${op}='")
    }
}

/** JS `%`: the sign of the dividend. Cangjie's `fmod` throws where JS gives NaN or `l`. */
func remainder(l: Float64, r: Float64): Float64 {
    if (l.isNaN() || r.isNaN() || l.isInf() || r == 0.0) {
        return Float64.NaN
    }
    if (r.isInf()) {
        return l
    }
    fmod(l, r)
}

/** JS `**`: unlike C `pow`, `x ** NaN` and `(±1) ** ±Infinity` are NaN. */
func power(base: Float64, exponent: Float64): Float64 {
    if (exponent.isNaN() || ((base == 1.0 || base == -1.0) && exponent.isInf())) {
        return Float64.NaN
    }
    base ** exponent
}

/** JS ToInt32. */
func toInt32(n: Float64): Int32 {
    if (n.isNaN() || n.isInf()) {
        return 0
    }
    let m = fmod(trunc(n), 4294967296.0)
    wrapInt32(Int64(if (m < 0.0) { m + 4294967296.0 } else { m }))
}

/** The low 32 bits of `n` as a signed integer. */
func wrapInt32(n: Int64): Int32 {
    let low = n & 0xFFFF_FFFF
    Int32(if (low >= 0x8000_0000) { low - 0x1_0000_0000 } else { low })
}

/** JS shift count: ToUint32(n) & 31. */
func shiftCount(n: Float64): Int64 {
    Int64(toInt32(n)) & 31
}

func bigIntOperator(op: String, l: BigInt, r: BigInt): BigInt {
    let zero = BigInt(0)
    match (op) {
        case "+" => l + r
        case "-" => l - r
        case "*" => l * r
        case "/" | "%" where r == zero => throw ExternCompoundAssignmentException("BigInt division by zero")
        case "/" => l / r
        case "%" => l % r
        case "**" where r < zero => throw ExternCompoundAssignmentException("BigInt negative exponent")
        case "**" => l ** UInt64(bigIntCount(op, r))
        case "&" => l & r
        case "|" => l | r
        case "^" => l ^ r
        case "<<" => shiftLeft(l, r)
        case ">>" => shiftLeft(l, -r)
        case _ => throw ExternCompoundAssignmentException("Unsupported compound assignment operator '${op}='")
    }
}

let MAX_COUNT = BigInt(Int64(Int32.Max))

/** `n << count` for any sign of `count`; a right shift rounds towards negative infinity. */
func shiftLeft(n: BigInt, count: BigInt): BigInt {
    if (count >= BigInt(0)) {
        return n << bigIntCount("<<", count)
    }
    if (-count > MAX_COUNT) {
        return if (n < BigInt(0)) { BigInt(-1) } else { BigInt(0) }
    }
    n >> (-count).toInt64()
}

/** A non-negative exponent or left shift count; JS fails with a RangeError for huge ones too. */
func bigIntCount(op: String, n: BigInt): Int64 {
    if (n > MAX_COUNT) {
        throw ExternCompoundAssignmentException("BigInt '${op}=' operand too large")
    }
    n.toInt64()
}
