import math
import sequtils
import strscans
import tables

import puyopuyo
import myUtil

type
  ConditionKind* = enum
    POP,                     # cぷよ全て消すべし
    POP_COLOR,               # n色消す
    POP_COLOR_MORE,          # n色以上消す
    POP_NUM,                 # cぷよn個消す
    POP_NUM_MORE,            # cぷよn個以上消す
    CHAIN,                   # n連鎖する
    CHAIN_MORE,              # n連鎖以上する
    CHAIN_POP,               # n連鎖する+cぷよ全て消す
    CHAIN_MORE_POP,          # n連鎖以上する+cぷよ全て消す
    POP_COLOR_SAMETIME,      # n色同時に消す
    POP_COLOR_MORE_SAMETIME, # n色以上同時に消す
    POP_NUM_SAMETIME,        # cぷよn個同時に消す
    POP_NUM_MORE_SAMETIME,   # cぷよn個以上同時に消す
    POP_POINT,               # cぷよn箇所同時に消す
    POP_POINT_MORE,          # cぷよn箇所以上同時に消す
    POP_CONNECT,             # cぷよn連結で消す
    POP_CONNECT_MORE         # cぷよn連結以上で消す
    NO_CONDITION             # 未設定

  Condition* = tuple
    kind: ConditionKind
    num: int # conditionのnにあたる部分
    color: Puyo # conditionのcにあたる部分、NONEの場合は全ぷよを表す
    extra: int # 余剰ぷよ数（kindがChainKindに含まれている場合のみ有効）

  Move* = tuple
    piece: Piece
    operation: Operation

  Nazopuyo* = tuple
    field: Field
    moveNum: int # 手数
    moves: seq[Move] # moves[i].operation.fixedPuyoX == 0なら未操作とする
    condition: Condition
    puyoNum: array[RED..GARBAGE, int] # フィールドとツモを合わせた各色のぷよの数

  SimultaneousNazopuyo* = tuple
    fields: seq[Field] # 連立された各なぞぷよのフィールド達
    conditions: seq[Condition] # 連立された各なぞぷよのクリア条件達
    moves: seq[(int, Move)] # 操作対象のなぞぷよ番号、操作 / int値が-1なら未操作とする
    nazoNum: int
    moveNum: int # 合計手数

var UseIpsFormat* = false

const
  NotUseColor* = {POP_COLOR, POP_COLOR_MORE, CHAIN, CHAIN_MORE,
      POP_COLOR_SAMETIME, POP_COLOR_MORE_SAMETIME}
  ChainKind* = {CHAIN, CHAIN_MORE, CHAIN_POP, CHAIN_MORE_POP}
  ChainMoreKind* = {CHAIN_MORE, CHAIN_MORE_POP}
  AllPopKind* = {POP, CHAIN_POP, CHAIN_MORE_POP}
  SupportedKind* = {POP, CHAIN, CHAIN_MORE, CHAIN_POP, CHAIN_MORE_POP} # 対応しているなぞぷよの種類
  NumCharacters = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ.-" # 数字用
  ConditionCharacters = "2abcduvwxEFGHIJQR"        # 条件用
  PiecesCharacters = "0coAM2eqCO4gsEQ6iuGS8kwIU"   # ツモ用
  OperationCharacters = "0coA2eqC4gsE6iuG8kwIamyK" # 操作用
  HeaderIshikawapuyo = "https://ishikawapuyo.net/simu/pn.html?"
  HeaderIps = "https://ips.karou.jp/simu/pn.html?"

# URLからなぞぷよパラメータへの逆引き用Table
var CharToNum = initTable[char, int]()
for i in 0..63:
  CharToNum[NumCharacters[i]] = i

var CharToCondition = initTable[char, ConditionKind]()
for i in 0..16:
  CharToCondition[ConditionCharacters[i]] = ConditionKind(i)

proc `$`*(nazo: Nazopuyo): string =
  ##[
    なぞぷよをURLに変換する

    Args:
      nazo (Nazopuyo): なぞぷよ

    Returns:
      string: なぞぷよのURL
  ]##
  # フィールドをURLに変換
  var fieldUrl = ""

  for i in countdown(13, 1):
    let row = nazo.field.main[i]
    for j in 1..3:
      fieldUrl.add NumCharacters[8 * row[2 * j - 1].ord + row[2 * j].ord]

  for i, c in fieldUrl:
    if c != '0':
      fieldUrl = fieldUrl[i..^1]
      break

  # ツモ・操作達をURLに変換
  var piecesUrl = "_"

  for m in nazo.moves:
    piecesUrl.add PiecesCharacters[5 * (m.piece[0].ord - 1) + (m.piece[1].ord - 1)]
    if m.operation.fixedPuyoX == 0:
      piecesUrl.add '1'
    else:
      piecesUrl.add OperationCharacters[4*(
          m.operation.fixedPuyoX-1)+m.operation.direction.ord]

  # 条件をURLに変換
  var conditionUrl = ""

  if nazo.condition.kind != NO_CONDITION:
    conditionUrl.add "__"
    conditionUrl.add ConditionCharacters[nazo.condition.kind.ord]

    if nazo.condition.kind in NotUseColor:
      conditionUrl.add '0'
    else:
      let tmp = nazo.condition.color.ord
      conditionUrl.add if tmp == 8: "7" else: $tmp

    if nazo.condition.kind != POP:
      conditionUrl.add NumCharacters[nazo.condition.num]
    else:
      conditionUrl.add '0'

  return (if UseIpsFormat: HeaderIps else: HeaderIshikawapuyo) & fieldUrl &
      piecesUrl & conditionUrl

proc toNazopuyo*(url: string): Nazopuyo =
  ##[
  URLからなぞぷよを生成する

  Args:
    url (string): なぞぷよのURL文字列

  Returns:
    Nazopuyo: 生成されたなぞぷよ

  Raises:
    ValueError: 不正な、あるいは未対応のURLを指定した時に発生

  Note:
    ~(チルダ)形式（固ぷよ、鉄ぷよを含む盤面のURL）、フィーバーなぞぷよには未対応
  ]##
  var prefix, fieldStr, movesStr, conditionStr: string
  discard scanf(url, "$*?$*_$*_$w", prefix, fieldStr, movesStr, conditionStr)

  if fieldStr[0] == '~': raise newException(ValueError, "\"~\"形式には未対応")

  # 盤面読み込み
  result.field.initialize
  for i in 0..<fieldStr.len:
    let
      n = CharToNum[fieldStr[^(i + 1)]]
      rightPuyo = Puyo(n mod 8) # 偶数列ぷよ
      leftPuyo = Puyo(n div 8)  # 奇数列ぷよ
      rightCol = 6 - i mod 3 * 2
      leftCol = rightCol - 1
      row = i div 3 + 1

    if rightPuyo != NONE:
      result.field.main[row][rightCol] = rightPuyo
      result.field.nextSetY[rightCol] = row + 1
      if RED <= rightPuyo and rightPuyo <= GARBAGE:
        result.field.existPuyoNum[rightPuyo][rightCol].inc
        result.puyoNum[rightPuyo].inc

    if leftPuyo != NONE:
      result.field.main[row][leftCol] = leftPuyo
      result.field.nextSetY[leftCol] = row + 1
      if RED <= leftPuyo and leftPuyo <= GARBAGE:
        result.field.existPuyoNum[leftPuyo][leftCol].inc
        result.puyoNum[leftPuyo].inc

  # ツモ、操作読み込み
  result.moveNum = movesStr.len div 2
  result.moves = @[]
  for i in 0..<result.moveNum:
    let
      pieceNum = CharToNum[movesStr[i * 2]]
      piece: Piece = [Puyo(pieceNum mod 12 div 2 + 1), Puyo(pieceNum div 12 + 1)]
      operationNum = CharToNum[movesStr[i * 2 + 1]]
    var op: Operation
    if operationNum == 1:
      op = (0, UP)
    else:
      op = (operationNum mod 12 div 2 + 1, Direction(operationNum div 12))
    result.moves.add (piece, op)
    result.puyoNum[piece[0]].inc
    result.puyoNum[piece[1]].inc

  # 条件読み込み
  if conditionStr == "":
    result.condition.kind = NO_CONDITION
    return result
  result.condition.kind = CharToCondition[conditionStr[1]]
  result.condition.color = Puyo(conditionStr[2].parseInt)
  result.condition.num = CharToNum[conditionStr[3]]
  let fieldColoredNum = result.field.existPuyoNum[ColorPuyoIter].foldl(a + b.sum, 0)
  if result.condition.kind in ChainKind:
    result.condition.extra = fieldColoredNum+result.moveNum*2-result.condition.num*4

proc clearMoves*(nazo: var Nazopuyo) =
  ##[
    なぞぷよの操作を消す

    Args:
      nazo (var Nazopuyo): なぞぷよ

    Returns:
      （なし）

    Note:
      境界条件チェックを一切行っていない
  ]##
  for i in 0..<nazo.moveNum:
    nazo.moves[i].operation.fixedPuyoX = 0

proc havePuyo(field: Field, color: Puyo): bool =
  ##[
    フィールド上に指定色があるかどうか判定する

    Args:
      field (Field): フィールド
      color (Puyo): あるかどうか判定する対象の色

    Returns:
      bool: あるかどうか

    Note:
      境界条件チェックを一切行っていない
  ]##
  case color
  of NONE, COLOR_PUYO:
    let iter = if color == NONE: PuyoIter else: ColorPuyoIter
    for p in iter:
      for x in 1..6:
        if field.existPuyoNum[p][x] != 0:
          return true

    return false
  else:
    for x in 1..6:
      if field.existPuyoNum[color][x] != 0:
        return true

    return false

proc clear*(nazo: Nazopuyo, popData: PopData): bool =
  ##[
    なぞぷよがクリア状態にあるかどうかを判定する

    Args:
      nazo (Nazopuyo): なぞぷよ（ある操作を行った直後）
      popData (PopData): ある操作によって得られた結果

    Returns:
      bool: クリアしたかどうか

    Raises:
      ValueError: 未対応の条件を指定した時に発生
  ]##
  case nazo.condition.kind
  of POP:
    return not nazo.field.havePuyo nazo.condition.color
  of CHAIN:
    return popData.chainNum == nazo.condition.num
  of CHAIN_MORE:
    return popData.chainNum >= nazo.condition.num
  of CHAIN_POP:
    return popData.chainNum == nazo.condition.num and
        not nazo.field.havePuyo nazo.condition.color
  of CHAIN_MORE_POP:
    return popData.chainNum >= nazo.condition.num and
        not nazo.field.havePuyo nazo.condition.color
  else:
    raise newException(ValueError, "未対応")

proc setReverseOperations*(nazo: var Nazopuyo, reverseOperations: seq[Operation]) =
  ##[
    なぞぷよに（逆順に格納された）操作列をセットする

    Args:
      nazo (var Nazopuyo): なぞぷよ
      reverseOperations (seq[Operation]): セットしたい操作列（逆順）

    Returns:
      （なし）

    Raises:
      ValueError: 解の長さがなぞぷよの手数より長い時に発生

    Note:
      解の長さがなぞぷよの手数より短い場合、前の手から埋めていく
  ]##
  let length = reverseOperations.len
  if length > nazo.moveNum:
    raise newException(ValueError, "reverseOperationが長すぎる")

  for i in 0..<length:
    nazo.moves[i].operation = reverseOperations[length-i-1]

proc toSimultaneousNazopuyo*(nazos: openArray[
    Nazopuyo]): SimultaneousNazopuyo =
  ##[
    なぞぷよ達をまとめて連立なぞぷよにする

    Args:
      nazos (openArray[Nazopuyo]): なぞぷよ達

    Returns:
      SimultaneousNazopuyo: 連立なぞぷよ

    Note:
      movesは単にnazos.movesを順に連結する
  ]##
  result.nazoNum = nazos.len
  result.fields = newSeq[Field](result.nazoNum)
  result.conditions = newSeq[Condition](result.nazoNum)
  for i, nazo in nazos:
    result.fields[i] = nazo.field
    result.conditions[i] = nazo.condition
    result.moveNum.inc nazo.moveNum
  result.moves = newSeqOfCap[(int, Move)](result.moveNum)
  for nazo in nazos:
    for m in nazo.moves:
      result.moves.add (-1, m)

proc setMoves*(simultaneousNazo: var SimultaneousNazopuyo, nazos: openArray[
    Nazopuyo], nazoidxes: openArray[int]){.inline.} =
  ##[
    連立なぞぷよにツモを設定する

    Args:
      simultaneousNazo (SimultaneousNazopuyo): 連立なぞぷよ
      nazos (openArray[Nazopuyo]): 連立なぞぷよ中の各なぞぷよ
      nazoidxes (openArray[int]): どの番号のなぞぷよのツモを使うか

    Returns:
      （なし）
  ]##
  var usedNum = newSeq[int](simultaneousNazo.nazoNum)
  for moveIdx in 0..<simultaneousNazo.moveNum:
    let nazoIdx = nazoidxes[moveIdx]
    simultaneousNazo.moves[moveIdx] = (-1, nazos[nazoIdx].moves[usedNum[nazoIdx]])
    usedNum[nazoIdx].inc

proc operatePiece*(nazo: var Nazopuyo, nextIdx: int,
    operation: Operation): PopData{.inline.} =
  ##[
    1手（ぷよ（ツモ）を置き、連鎖スタート）進める

    Args:
      nazo (var Nazopuyo): なぞぷよ
      nextIdx (int): 置くツモの添字
      operation (Operation): ツモを置く位置

    Returns:
      PopData: 連鎖が終わって得られた結果
  ]##

  result = nazo.field.operatePiece(nazo.moves[nextIdx].piece, operation)
  for p in PuyoIter:
    nazo.puyoNum[p].dec result.popNum[p]

proc undo*(nazo: var Nazopuyo, field: Field, popData: PopData){.inline.} =
  ##[
    1手前の状態に戻す

    Args:
      nazo (var Nazopuyo): なぞぷよ（操作後）
      field (Field): 操作前のフィールド
      popData (PopData): 操作によって得られた結果

    Returns:
      （なし）
  ]##
  nazo.field = field
  for p in PuyoIter:
    nazo.puyoNum[p].inc popData.popNum[p]

proc setPuyoNum*(nazo: var Nazopuyo){.inline.} =
  ##[
    フィールドとツモが設定されているなぞぷよの、puyoNumを設定する

    Args:
      nazo (var Nazopuyo): フィールドとツモが設定されているなぞぷよ

    Returns:
      （なし）

    Note:
      境界条件チェックは行っていない
  ]##
  for y in 1..13:
    for x in 1..6:
      nazo.puyoNum[nazo.field.main[y][x]].inc

  for m in nazo.moves:
    nazo.puyoNum[m.piece[0]].inc
    nazo.puyoNum[m.piece[1]].inc

