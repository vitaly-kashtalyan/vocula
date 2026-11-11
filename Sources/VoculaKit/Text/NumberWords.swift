import Foundation

enum NumberWords {
  static let exact: Set<String> = [
    "два", "две", "двум", "двумя", "три", "трём", "трем", "тремя", "семь", "семи",
    "сто", "ста", "двести", "триста",
    "дві", "двом", "двома", "трьом", "трьома", "сім", "двісті",
    "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
    "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen",
    "eighteen", "nineteen", "twenty", "thirty", "forty", "fifty", "sixty", "seventy",
    "eighty", "ninety",
    "dwa", "dwie", "dwaj", "dwóch", "dwom", "dwóm", "dwoma",
    "trzy", "trzej", "trzech", "trzem", "trzema", "ośmiu", "ośmioma",
    "sto", "stu", "dwieście", "dwustu", "trzysta", "trzystu",
  ]

  static let stems = [
    "двух", "трех", "трёх", "четыр", "пять", "пяти", "пятнадц", "шесть", "шести", "шестнадц",
    "семнадц", "семьдес", "семидес", "семьсот", "семисот", "восем", "восьм", "девят",
    "девяност", "десят", "одиннадц", "двенадц", "тринадц", "двадц", "тридц", "сорок",
    "тысяч", "миллион", "миллиард",
    "двох", "трьох", "чотир", "пятдесят", "пятсот", "шіст", "сімнадц", "сімдес", "сімсот",
    "вісім", "вісьм", "одинадц", "дванадц", "тисяч", "мільйон", "мільярд",
    "hundred", "thousand", "million", "billion",
    "czter", "pięć", "pięci", "piętna", "sześć", "sześci", "szesna", "siedem", "siedmi",
    "osiem", "dziewię", "dziesię", "jedena", "dwana", "dwuna", "trzyna", "dwadzie",
    "dwudzie", "trzydzie", "tysiąc", "tysięc", "milion", "miliard",
  ]

  static func groups(in text: String) -> [String] {
    let polish = RefinementPolicy.uses(Negations.polishLetters, text)
    return RefinementPolicy.words(in: text)
      .split { !isNumber($0) || (polish && $0 == "ten") }
      .map { $0.joined(separator: " ") }
  }

  static func isNumber(_ word: String) -> Bool {
    exact.contains(word) || stems.contains(where: word.hasPrefix)
  }
}
