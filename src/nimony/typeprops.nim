include nifprelude
import nimony_model, decls, xints, semdata, programs, nifconfig

const
  DefaultSetElements* = createXint(1'u64 shl 8)
  MaxSetElements* = createXint(1'u64 shl 16)

proc typebits*(config: NifConfig; n: PackedToken): int =
  if n.kind == IntLit:
    result = pool.integers[n.intId]
  elif n.kind == InlineInt:
    result = n.soperand
  else:
    result = 0
  if result == -1:
    result = config.bits

proc isOrdinalType*(typ: TypeCursor; allowEnumWithHoles: bool = false): bool =
  case typ.kind
  of Symbol:
    let s = tryLoadSym(typ.symId)
    if s.status != LacksNothing:
      return false
    if s.decl.symKind != TypeY:
      return false
    let decl = asTypeDecl(s.decl)
    case decl.body.typeKind
    of EnumT:
      if not allowEnumWithHoles:
        # check for holes
        var field = asEnumDecl(decl.body).firstField
        var last: xint
        let firstVal = asEnumField(field).val
        case firstVal.kind
        of IntLit:
          last = createXint pool.integers[firstVal.intId]
        of UIntLit:
          last = createXint pool.uintegers[firstVal.uintId]
        else:
          # enum field with non int/uint value?
          return false
        skip field
        while field.kind != ParRi:
          let val = asEnumField(field).val
          var thisVal: xint
          case val.kind
          of IntLit:
            thisVal = createXint pool.integers[val.intId]
          of UIntLit:
            thisVal = createXint pool.uintegers[val.uintId]
          else:
            # enum field with non int/uint value?
            return false
          inc last
          if thisVal != last:
            return false
          skip field
      result = true
    of DistinctT:
      # check base type
      var baseType = decl.body
      inc baseType # skip distinct tag
      result = isOrdinalType(baseType)
    else:
      result = isOrdinalType(decl.body)
  of ParLe:
    case typ.typeKind
    of IntT, UIntT, CharT, BoolT:
      result = true
    of InvokeT:
      # check base type
      var base = typ
      inc base # skip invoke tag
      result = isOrdinalType(base)
    else:
      result = false
  else:
    result = false

proc firstOrd*(c: var SemContext; typ: TypeCursor): xint =
  case typ.kind
  of Symbol:
    let s = tryLoadSym(typ.symId)
    if s.status != LacksNothing:
      result = createNaN()
      return
    if s.decl.symKind != TypeY:
      result = createNaN()
      return
    let decl = asTypeDecl(s.decl)
    case decl.body.typeKind
    of EnumT:
      var field = asEnumDecl(decl.body).firstField
      let firstVal = asEnumField(field).val
      case firstVal.kind
      of IntLit:
        result = createXint pool.integers[firstVal.intId]
      of UIntLit:
        result = createXint pool.uintegers[firstVal.uintId]
      else:
        # enum field with non int/uint value?
        result = createNaN()
    of DistinctT:
      # check base type
      var baseType = decl.body
      inc baseType # skip distinct tag
      result = firstOrd(c, baseType)
    else:
      result = firstOrd(c, decl.body)
  of ParLe:
    case typ.typeKind
    of IntT:
      var bits = typ
      inc bits # skip int tag
      case typebits(c.g.config, bits.load)
      of 8: result = createXint low(int8).int64
      of 16: result = createXint low(int16).int64
      of 32: result = createXint low(int32).int64
      of 64: result = createXint low(int64)
      else: result = createNaN()
    of UIntT, CharT, BoolT:
      result = zero()
    of InvokeT:
      # check base type
      var base = typ
      inc base # skip invoke tag
      result = firstOrd(c, base)
    else:
      result = createNaN()
  else:
    result = createNaN()

proc lastOrd*(c: var SemContext; typ: TypeCursor): xint =
  case typ.kind
  of Symbol:
    let s = tryLoadSym(typ.symId)
    if s.status != LacksNothing:
      result = createNaN()
      return
    if s.decl.symKind != TypeY:
      result = createNaN()
      return
    let decl = asTypeDecl(s.decl)
    case decl.body.typeKind
    of EnumT:
      # check for holes
      var field = asEnumDecl(decl.body).firstField
      var last = field
      while field.kind != ParRi:
        last = field
        skip field
      let lastVal = asEnumField(field).val
      case lastVal.kind
      of IntLit:
        result = createXint pool.integers[lastVal.intId]
      of UIntLit:
        result = createXint pool.uintegers[lastVal.uintId]
      else:
        # enum field with non int/uint value?
        result = createNaN()
    of DistinctT:
      # check base type
      var baseType = decl.body
      inc baseType # skip distinct tag
      result = lastOrd(c, baseType)
    else:
      result = lastOrd(c, decl.body)
  of ParLe:
    case typ.typeKind
    of IntT:
      var bits = typ
      inc bits # skip int tag
      case typebits(c.g.config, bits.load)
      of 8: result = createXint high(int8).int64
      of 16: result = createXint high(int16).int64
      of 32: result = createXint high(int32).int64
      of 64: result = createXint high(int64)
      else: result = createNaN()
    of UIntT, CharT:
      var bits = typ
      inc bits # skip int tag
      case typebits(c.g.config, bits.load)
      of 8: result = createXint high(uint8).uint64
      of 16: result = createXint high(uint16).uint64
      of 32: result = createXint high(uint32).uint64
      of 64: result = createXint high(uint64)
      else: result = createNaN()
    of BoolT:
      result = createXint 1.uint64
    of InvokeT:
      # check base type
      var base = typ
      inc base # skip invoke tag
      result = lastOrd(c, base)
    else:
      result = createNaN()
  else:
    result = createNaN()

proc lengthOrd*(c: var SemContext; typ: TypeCursor): xint =
  let first = firstOrd(c, typ)
  if first.isNaN: return first
  let last = lastOrd(c, typ)
  if last.isNaN: return last
  result = last - first + createXint(1.uint64)
