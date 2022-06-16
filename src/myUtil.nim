import algorithm
import math
import random
import sequtils
import strutils

template myChoice*(iter: untyped, choiceNum: int): untyped =
  ##[
    イテラブルから、いくつかの要素を重複なく選択する

    Args:
      iter (untyped): 要素を選ぶ配列・動的配列
      choiceNum (int): 選ぶ数

    Returns:
      untyped: 選ばれた要素からなる動的配列

    Raises:
      ValueError: choiceNumに負の数を入力すると発生

    Examples:
      >>> assert ([12, 18, 21, 25].myChoice 2) == @[21, 12]
      >>> assert ((1..5).myChoice 2) == @[5, 3]

    Note:
      この関数を呼ぶ前に、randomize()を呼ぶ必要がある
      iterはイテラブル（toSeqを持つタイプ）を要求する
  ]##
  if choiceNum < 0:
    raise newException(ValueError, "choiceNumは0以上のみ受け付ける")
  elif choiceNum == 0:
    @[]
  else:
    var result = iter.toSeq
    result.shuffle
    result[0..<choiceNum]

proc myDistribute*(allNum, distributeNum: int, allowZero: bool): seq[int] =
  ##[
    ある整数を、ランダムにいくつかの整数に分ける

    Args:
      allNum (int): 分けられる数
      distributeNum (int): いくつに分けるか
      allowZero (bool): 0が出るのを許容するかどうか

    Returns:
      seq[int]: 分けた結果の動的配列

    Raises:
      ValueError: allNum、distributeNumに負の数を入力したり、分けられない入力をしたりすると発生

    Examples:
      >>> assert myDistribute(12, 4, false) == @[2, 5, 1, 4]

    Note:
      この関数を呼ぶ前に、randomize()を呼ぶ必要がある
  ]##
  if distributeNum <= 0 or allNum < 0 or (allNum < distributeNum and
      not allowZero):
    raise newException(ValueError, "分けられない組み合わせ")
  if distributeNum == 1:
    return @[allNum]
  if allNum == 0:
    return newSeq[int](distributeNum)

  # 「しきり」を入れる高校数学の場合の数っぽいアルゴリズム
  var partitions: seq[int]
  if allowZero:
    partitions = newSeqWith(distributeNum-1, rand allNum)
  else:
    partitions = (1..allNum-1).myChoice distributeNum-1
  partitions.sort

  result.add partitions[0]
  for i in 0..<distributeNum-2:
    result.add partitions[i+1]-partitions[i]
  result.add allNum-partitions[distributeNum-2]

proc parseInt*(c: char): int{.inline.} =
  ##[
    文字を整数値に変換する

    Args:
      c (char): 数字（0〜9）

    Returns:
      int: 変換後の数値

    Raises:
      ValueError: cが'0'〜'9'でない場合に発生
  ]##
  if not c.isDigit:
    raise newException(ValueError, "'0'〜'9'のみ受け付ける")
  return c.int - '0'.int

proc safeParseInt*(s: string): (bool, int){.inline.} =
  ##[
    文字列を整数値に変換する、変換できなくても例外を投げない

    Args:
      s (string): 数値に変換したい文字列

    Returns:
      bool: 変換に成功したかどうか
      int: 変換後の数値
  ]##

  for c in s[1..^1]:
    if not c.isDigit:
      return (false, 0)

  if s[0] == '-' or s[0].isDigit:
    return (true, s.parseInt)
  else:
    return (false, 0)

proc homoProduct*(endNum, length: int): seq[seq[int]] =
  ##[
    0-indexedの重複順列を返す

    Args:
      endNum (int): 出てくる数の最大値+1、順列的に言えばモノの種類数
      length (int): 返す動的配列の長さ

    Returns:
      seq[seq[int]]: 重複順列を表す動的配列の動的配列

    Examples:
      >>> assert homoProduct(2, 2) == @[@[0, 0], @[0, 1], @[1, 0], @[1, 1]]

    Note:
      境界条件チェックは行っていない
  ]##
  let resultLen = endNum^length
  for num in 0..<resultLen:
    var
      tmp = num
      permutation = newSeq[int](length)
    for power in countdown(length-1, 0):
      let divisor = endNum^power
      permutation[length-1-power] = tmp div divisor
      tmp = tmp mod divisor
    result.add permutation
