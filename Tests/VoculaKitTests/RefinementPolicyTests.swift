import Testing

@testable import VoculaKit

@Suite("Refinement policy")
struct RefinementPolicyTests {
  @Test("text too short to hold filler is not worth a second of latency")
  func shortTextSkips() {
    #expect(RefinementPolicy.shouldRun(isEnabled: true, text: "yes") == false)
  }

  @Test("an ordinary transcript runs")
  func ordinaryRuns() {
    #expect(RefinementPolicy.shouldRun(isEnabled: true, text: "so um I think we should ship it"))
  }

  @Test("a short phrase is given seconds, a long one is given more")
  func deadlineGrowsWithLength() {
    let short = RefinementPolicy.deadline(for: "восемь слов тут", ceiling: .seconds(30))
    let long = RefinementPolicy.deadline(
      for: String(repeating: "слово ", count: 200), ceiling: .seconds(30))
    #expect(short < long)
    #expect(short >= .seconds(2))
  }

  @Test("the ceiling is never exceeded, however long the transcript")
  func ceilingHolds() {
    #expect(
      RefinementPolicy.deadline(for: String(repeating: "a", count: 100_000), ceiling: .seconds(30))
        == .seconds(30))
  }

  @Test("slow is twice what was measured: 0.48 s a pass, 4.8 ms a character")
  func slowFloor() {
    #expect(!RefinementPolicy.isSlow(.milliseconds(950), characters: 12))
    #expect(RefinementPolicy.isSlow(.milliseconds(970), characters: 12))
    #expect(!RefinementPolicy.isSlow(.milliseconds(8_000), characters: 842))
    #expect(RefinementPolicy.isSlow(.milliseconds(8_200), characters: 842))
  }

  @Test("an empty result is refused")
  func emptyIsRefused() {
    #expect(RefinementPolicy.verdict(on: "   ", original: "the original") == .refused(.empty))
  }

  @Test("a result many times longer than the input is refused")
  func runawayIsRefused() {
    let runaway = String(repeating: "a mutex is a synchronisation primitive. ", count: 20)
    #expect(
      RefinementPolicy.verdict(on: runaway, original: "what is a mutex") == .refused(.runaway))
  }

  @Test("an ordinary result is accepted and trimmed")
  func ordinaryIsAccepted() {
    #expect(
      RefinementPolicy.verdict(on: "  Cleaned text.  ", original: "cleaned text")
        == .accepted("Cleaned text."))
  }

  @Test("a line break from the model is folded away, so a terminal never receives Return")
  func producedTextIsOneLine() {
    #expect(
      RefinementPolicy.verdict(
        on: "Первая строка.\nВторая строка.\r\n\tТретья.",
        original: "первая строка вторая строка третья")
        == .accepted("Первая строка. Вторая строка. Третья."))
  }

  @Test("the guards judge the folded text, not the raw one")
  func guardsSeeTheFoldedText() {
    let padded = "Cleaned" + String(repeating: "\n", count: 40) + "text."
    #expect(
      RefinementPolicy.verdict(on: padded, original: "cleaned text") == .accepted("Cleaned text."))
    #expect(RefinementPolicy.verdict(on: "same\ntext", original: "same text") == .unchanged)
  }

  @Test("a result that lost half the text is refused")
  func truncationIsRefused() {
    let original =
      "Опять же, пока сухо, листья можно убирать в дальнем углу, либо у забора, "
      + "чтобы потом в случае дождя можно было всё это вывезти."
    #expect(
      RefinementPolicy.verdict(on: "Можно убрать в углу.", original: original)
        == .refused(.truncated))
  }

  @Test("ordinary editing is nowhere near the truncation floor")
  func ordinaryEditingSurvives() {
    let original = "Ну вот, значит, на сервере это работает, и поэтому появилась новая задача."
    let out = "Ну вот, на сервере это работает, и поэтому появилась новая задача."
    #expect(RefinementPolicy.verdict(on: out, original: original) == .accepted(out))
  }

  @Test("a dropped negation is refused — it reverses the sentence and nothing else sees it")
  func lostNegationIsRefused() {
    #expect(
      RefinementPolicy.verdict(
        on: "Это работает у меня на компьютере.",
        original: "Это не работает у меня на компьютере.") == .refused(.negationChanged))
  }

  @Test("an ADDED negation is refused too — it reverses the sentence just as hard")
  func gainedNegationIsRefused() {
    #expect(
      RefinementPolicy.verdict(
        on: "Это не работает у меня на компьютере.",
        original: "Это работает у меня на компьютере.") == .refused(.negationChanged))
  }

  @Test(
    "a dropped or added particle is caught beside a word that merely starts like a negation",
    arguments: [
      ("несколько тестов не проходят", "Несколько тестов проходят."),
      ("Это работает уже неделю", "Это не работает уже неделю."),
      ("это необходимо, но не срочно", "Это необходимо и срочно."),
      ("это не работает и нет времени", "Это работает, и нет времени."),
    ])
  func aPrefixDoesNotMaskAParticle(original: String, produced: String) {
    #expect(
      RefinementPolicy.verdict(on: produced, original: original) == .refused(.negationChanged))
  }

  @Test(
    "every negation is counted, so losing one of two is refused",
    arguments: [
      ("Это не работает, и я не знаю почему.", "Это работает, и я не знаю почему."),
      ("It doesn't build and I don't know why.", "It builds and I don't know why."),
    ])
  func negationsAreCounted(original: String, produced: String) {
    #expect(
      RefinementPolicy.verdict(on: produced, original: original) == .refused(.negationChanged))
  }

  @Test("a negation moved onto another word is refused, though the count is the same")
  func aNegationStaysOnItsWord() {
    #expect(
      RefinementPolicy.verdict(
        on: "Я хочу идти, но не пойду.", original: "Я не хочу идти, но пойду")
        == .refused(.negationChanged))
  }

  @Test("a negation whose word was rewritten has nothing to stay on, and is accepted")
  func aRewrittenWordFreesItsNegation() {
    let out = "Это не слишком хорошо работает."
    #expect(
      RefinementPolicy.verdict(on: out, original: "ну это не очень хорошо работает")
        == .accepted(out))
  }

  @Test("a new word that starts like a negation does not excuse a lost particle")
  func anUnrelatedPrefixedWordExcusesNothing() {
    #expect(
      RefinementPolicy.verdict(
        on: "Мы недавно обновили сервер.", original: "Мы не обновляли сервер в последнее время")
        == .refused(.negationChanged))
  }

  @Test(
    "a word that merely starts like a negation negates nothing",
    arguments: [
      ("там пара тестов падает на CI", "Несколько тестов падает на CI."),
      ("кто-нибудь посмотрел этот код", "Кто-то посмотрел этот код?"),
      ("the uncle said so", "The uncle said so."),
    ])
  func aPrefixAloneIsNotANegation(original: String, produced: String) {
    #expect(RefinementPolicy.verdict(on: produced, original: original) == .accepted(produced))
  }

  @Test(
    "Ukrainian, Polish and English negating words are counted",
    arguments: [
      ("я ніколи не був на цій зустрічі", "Я не був на цій зустрічі."),
      ("ніхто не прийшов, і це дивно", "Хтось не прийшов, і це дивно."),
      ("у мене немає часу", "У мене є час."),
      ("nobody tested this build", "Somebody tested this build."),
      ("it is nowhere to be found", "It is easy to find."),
      ("Nikt nie przyszedł na spotkanie", "Ktoś nie przyszedł na spotkanie."),
      ("Nigdy nie byłem w Krakowie", "Nie byłem w Krakowie."),
      ("Nic nie działa na serwerze", "Coś nie działa na serwerze."),
      ("Żaden test nie przeszedł", "Jakiś test nie przeszedł."),
      ("Zrobiłem to bez testów", "Zrobiłem to z testami."),
    ])
  func moreCarriersAreCounted(original: String, produced: String) {
    #expect(
      RefinementPolicy.verdict(on: produced, original: original) == .refused(.negationChanged))
  }

  @Test(
    "a negation moving into a word new to the result is not an inversion",
    arguments: [
      ("ну это не может быть", "Это невозможно."),
      ("это сделано не правильно", "Это сделано неправильно."),
      ("не может быть, чтобы это работало", "Невозможно, чтобы это работало."),
      ("это не правильно", "Это неправильно."),
      ("to jest nie możliwe", "To jest niemożliwe."),
    ])
  func aParticleMayMoveIntoAWord(original: String, produced: String) {
    #expect(RefinementPolicy.verdict(on: produced, original: original) == .accepted(produced))
  }

  @Test(
    "a negation carried inside a word still may not vanish",
    arguments: [
      ("это неправильно", "Это правильно."),
      ("это неправильно", "это правильно"),
      ("это невозможно сделать", "Это возможно сделать."),
      ("так делать нельзя", "Так делать можно."),
      ("To jest niemożliwe do zrobienia dzisiaj", "To jest możliwe do zrobienia dzisiaj."),
      ("this is unsafe to deploy", "This is safe to deploy."),
    ])
  func aCarrierMayNotVanish(original: String, produced: String) {
    #expect(
      RefinementPolicy.verdict(on: produced, original: original) == .refused(.negationChanged))
  }

  @Test(
    "an English contraction carries its negation",
    arguments: [
      ("this doesn't work on my machine", "This works on my machine."),
      ("this doesn’t work on my machine", "This works on my machine."),
      ("this doesnʼt work on my machine", "This works on my machine."),
      ("this works on my machine", "This doesnʼt work on my machine."),
      ("I can't do it today", "I can do it today."),
      ("we won’t ship it this week", "We will ship it this week."),
      ("this cannot work at all", "This can work at all."),
    ])
  func aContractionIsANegation(original: String, produced: String) {
    #expect(
      RefinementPolicy.verdict(on: produced, original: original) == .refused(.negationChanged))
  }

  @Test(
    "contracting or expanding a negation is not an inversion",
    arguments: [
      ("I do not know what happened", "I don't know what happened."),
      ("I cannot come today", "I can't come today."),
      ("we won't ship it this week", "We will not ship it this week."),
      ("I do not think so", "I don't think so."),
    ])
  func contractingIsNotAnInversion(original: String, produced: String) {
    #expect(RefinementPolicy.verdict(on: produced, original: original) == .accepted(produced))
  }

  @Test(
    "Polish \"no\" means \"well\", so dropping it is filler removal",
    arguments: [
      ("No dobra, zrobię to jutro rano", "Dobra, zrobię to jutro rano."),
      ("No, zrobię to jutro rano", "Zrobię to jutro rano."),
      (
        "Yyy, no, pociąg odjeżdża o 8:15 i jedzie mniej więcej cztery godziny.",
        "Pociąg odjeżdża o 8:15 i jedzie mniej więcej cztery godziny."
      ),
    ])
  func polishNoIsFiller(original: String, produced: String) {
    #expect(RefinementPolicy.verdict(on: produced, original: original) == .accepted(produced))
  }

  @Test(
    "\"no\" stays a negation outside Polish, and Polish keeps its own",
    arguments: [
      ("No problems were found in the build", "Problems were found in the build."),
      ("No funciona en mi máquina", "Funciona en mi máquina."),
      ("No, to nie działa", "No, to działa."),
      ("Tell Paweł there is no budget for this", "Tell Paweł there is budget for this."),
      ("No, it is not ready", "It is ready."),
      ("No, deploy it on Monday", "Deploy it on Monday."),
      ("Nie, no budżet nie wystarczy", "Budżet wystarczy."),
    ])
  func noIsANegationElsewhere(original: String, produced: String) {
    #expect(
      RefinementPolicy.verdict(on: produced, original: original) == .refused(.negationChanged))
  }

  @Test(
    "a question that comes back as a statement is refused",
    arguments: [
      ("Почему это не работает?", "Это не работает."),
      ("so why does the build fail on CI?", "The build fails on CI."),
      ("这个为何不工作？", "这个不工作。"),
    ])
  func aQuestionMayNotBecomeAStatement(original: String, produced: String) {
    #expect(RefinementPolicy.verdict(on: produced, original: original) == .refused(.questionLost))
  }

  @Test("a question mark the recogniser left out may be added")
  func aMissingQuestionMarkMayBeAdded() {
    let out = "Почему это не работает?"
    #expect(RefinementPolicy.verdict(on: out, original: "почему это не работает") == .accepted(out))
  }

  @Test("a rewrite that leaves the negations alone is accepted")
  func sameNegationCountIsFine() {
    let out = "Это не работает у меня на компьютере."
    #expect(
      RefinementPolicy.verdict(on: out, original: "это не работает у меня на компьютере")
        == .accepted(out))
  }

  @Test("a vanished quantity is refused — the real failure that no other guard saw")
  func lostNumberIsRefused() {
    #expect(
      RefinementPolicy.verdict(
        on:
          "Список покупок: один зеленый огурец, две большие банки томатной пасты и пачка макарон.",
        original:
          "список покупок, один зеленый огурец, две больших банки томатной пасты и пачки 4 макарон."
      )
        == .refused(.numberLost))
  }

  @Test("writing a spoken number as a digit is not a loss")
  func normalisingToDigitsIsFine() {
    let out = "Дай мне 2 ложки."
    #expect(RefinementPolicy.verdict(on: out, original: "дай мне две ложки") == .accepted(out))
  }

  @Test(
    "a number spoken as a word may not vanish — the failure that once got this pass rejected",
    arguments: [
      ("Купи четыре ложки сахара и молоко", "Купи ложки сахара и молоко."),
      ("add three more tests", "Add more tests."),
      ("Kup cztery jabłka", "Kup jabłka."),
      ("give me ten minutes to finish", "Give me minutes to finish."),
    ])
  func lostNumberWordIsRefused(original: String, produced: String) {
    #expect(RefinementPolicy.verdict(on: produced, original: original) == .refused(.numberLost))
  }

  @Test(
    "a number word that stays, or comes back as a new digit, is accepted",
    arguments: [
      ("купи четыре ложки сахара", "Купи 4 ложки сахара."),
      ("ну давай через пять минут", "Давай через пять минут."),
      ("about twenty people came", "About 20 people came."),
      ("через двадцать пять минут", "Через 25 минут."),
    ])
  func keptNumberWordIsFine(original: String, produced: String) {
    #expect(RefinementPolicy.verdict(on: produced, original: original) == .accepted(produced))
  }

  @Test("Polish \"ten\" means \"this\", so dropping it loses no number")
  func polishTenIsNotANumber() {
    let out = "Zrobię to jutro rano."
    #expect(
      RefinementPolicy.verdict(on: out, original: "Ten, wiesz, zrobię to jutro rano")
        == .accepted(out))
  }

  @Test("a number that stays put is accepted")
  func keptNumberIsFine() {
    let out = "И 4 пачки макарон."
    #expect(RefinementPolicy.verdict(on: out, original: "и пачки 4 макарон") == .accepted(out))
  }

  @Test(
    "grouping the thousands of a number is not a loss",
    arguments: [
      ("заплатили 1000 рублей", "Заплатили 1 000 рублей."),
      ("заплатили 1000 рублей", "Заплатили 1\u{00A0}000 рублей."),
      ("заплатили 15000 рублей", "Заплатили 15\u{2009}000 рублей."),
      ("заплатили 1 000 000 рублей", "Заплатили 1000000 рублей."),
      ("we paid 1,000 dollars", "We paid 1000 dollars."),
    ])
  func digitGroupsAreOneNumber(original: String, produced: String) {
    #expect(RefinementPolicy.verdict(on: produced, original: original) == .accepted(produced))
  }

  @Test("a decimal comma is not a thousands separator")
  func aDecimalCommaStays() {
    #expect(
      RefinementPolicy.verdict(on: "3,5 литра.", original: "3,5 литра") == .accepted("3,5 литра."))
    #expect(
      RefinementPolicy.verdict(on: "35 литра.", original: "3,5 литра") == .refused(.numberLost))
  }

  @Test("numbers side by side are not read as one group")
  func separateNumbersStaySeparate() {
    let out = "Этажи 3, 15 и 7 закрыты."
    #expect(RefinementPolicy.verdict(on: out, original: "этажи 3 15 и 7 закрыты") == .accepted(out))
  }

  @Test("an ideograph with a numeric value is not a digit")
  func ideographsAreNotDigits() {
    let out = "我明天再仔细看看。"
    #expect(RefinementPolicy.verdict(on: out, original: "嗯，那个什么，我明天再仔细看看") == .accepted(out))
  }

  @Test("one of two identical numbers going missing is still a loss")
  func repeatedNumbersAreCounted() {
    #expect(
      RefinementPolicy.verdict(
        on: "Возьми 5 ложек и ложку сахара.", original: "возьми 5 ложек и 5 ложек сахара")
        == .refused(.numberLost))
  }

  @Test("a Russian transcript answered in English is refused")
  func translationIsRefused() {
    #expect(
      RefinementPolicy.verdict(
        on: "Make a push to the repository and deploy.",
        original: "Делай push в репозитории и давай деплоить.") == .refused(.translated))
  }

  @Test("an English term inside Russian speech is not a translation")
  func aBorrowedTermIsFine() {
    let out = "Делай push в репозиторий и давай деплоить."
    #expect(
      RefinementPolicy.verdict(on: out, original: "Делай push в репозитории и давай деплоить.")
        == .accepted(out))
  }

  @Test("English in, English out is left alone")
  func englishStaysEnglish() {
    let out = "So what is a mutex anyway?"
    #expect(
      RefinementPolicy.verdict(on: out, original: "so what is a mutex anyway")
        == .accepted(out))
  }

  @Test("a sentence half made of English terms keeps both alphabets and is accepted")
  func mixedSpeechIsNeverRefused() {
    let spoken = "обнови build script и залей в staging server"
    let out = "Обнови build script и залей в staging server."
    #expect(RefinementPolicy.verdict(on: out, original: spoken) == .accepted(out))
  }

  @Test(
    "a translation within one alphabet is refused when the language's own letters vanish",
    arguments: [
      ("Zrób to jutro rano, proszę", "Do it tomorrow morning, please."),
      ("Я завтра перевірю, чи це працює", "Я завтра проверю, работает ли это."),
      ("Ich prüfe das morgen früh", "I will check it tomorrow morning."),
      ("Zrób to, proszę", "Do it, please."),
      ("Я перевірю це", "Я проверю это."),
    ])
  func ownLettersMustSurvive(original: String, produced: String) {
    #expect(RefinementPolicy.verdict(on: produced, original: original) == .refused(.translated))
  }

  @Test(
    "a clean-up that keeps the language keeps its letters",
    arguments: [
      ("ну я завтра перевірю чи це працює", "Я завтра перевірю, чи це працює."),
      ("Słuchaj, zrób to jutro rano, proszę", "Zrób to jutro rano, proszę."),
      ("памʼять на сервері закінчується", "Пам’ять на сервері закінчується."),
      ("мои\u{306} сервер перезагружается", "Мой сервер перезагружается."),
    ])
  func ownLettersSurviveACleanUp(original: String, produced: String) {
    #expect(RefinementPolicy.verdict(on: produced, original: original) == .accepted(produced))
  }

  @Test(
    "the language's own letters may vanish with the filler or the brand that carried them",
    arguments: [
      (
        "No więc, wiesz, ten serwer znowu nie odpowiada i nie wiem dlaczego.",
        "Ten serwer znowu nie odpowiada i nie wiem dlaczego."
      ),
      ("Ну, і я завтра подивлюся", "Я завтра подивлюся."),
      ("запуш це на гітхаб будь ласка", "Запуш це на GitHub, будь ласка."),
    ])
  func ownLettersMayLeaveWithTheirWord(original: String, produced: String) {
    #expect(RefinementPolicy.verdict(on: produced, original: original) == .accepted(produced))
  }

  @Test(
    "a translation that keeps the alphabet is refused, because it replaces almost every word",
    arguments: [
      (
        "Mam pytanie, czy masz czas jutro rano?",
        "I have a question, do you have time tomorrow morning?"
      ),
      ("Quiero comprar un coche nuevo para mi hermano", "I want to buy a new car for my brother."),
      ("Ich habe morgen keine Zeit, sorry", "I don't have time tomorrow, sorry."),
      ("Я сейчас работаю дома, приходи", "Я зараз працюю вдома, приходь."),
    ])
  func mostWordsReplacedIsATranslation(original: String, produced: String) {
    #expect(RefinementPolicy.verdict(on: produced, original: original) == .refused(.translated))
  }

  @Test("a clean-up keeps most of the words it was given")
  func aCleanUpKeepsItsWords() {
    let out = "Запушь в GitHub, пожалуйста."
    #expect(
      RefinementPolicy.verdict(on: out, original: "запушь в гитхаб пожалуйста") == .accepted(out))
  }

  @Test("a few words left after the filler is gone are too few to call a translation")
  func aShortResultIsNotJudgedByOverlap() {
    #expect(
      RefinementPolicy.verdict(
        on: "Завтра будет релиз.", original: "ну короче я хотел сказать что завтра будет релиз")
        != .refused(.translated))
  }

  @Test(
    "an alphabet the original did not use may not appear",
    arguments: [
      ("Please review the PR before lunch", "Пожалуйста, посмотри PR до обеда."),
      ("Я завтра проверю, работает ли это", "Я завтра перевірю, чи це працює."),
    ])
  func aNewAlphabetIsATranslation(original: String, produced: String) {
    #expect(RefinementPolicy.verdict(on: produced, original: original) == .refused(.translated))
  }

  @Test("Latin may appear, because a recogniser spells a brand in Cyrillic")
  func latinMayAppear() {
    let out = "Запушь в GitHub."
    #expect(RefinementPolicy.verdict(on: out, original: "запушь в гитхаб") == .accepted(out))
  }

  @Test("a mixed sentence translated whole is refused — the real case that refuted a threshold")
  func mixedSpeechTranslatedIsRefused() {
    #expect(
      RefinementPolicy.verdict(
        on: "Update the build script and push the staging server. Check all the logs.",
        original: "Обнови build script и залей в staging server. Проверь потом все логи сборки.")
        == .refused(.translated))
  }

  @Test("one Russian word among English ones must survive")
  func aSingleRussianWordIsEnough() {
    #expect(
      RefinementPolicy.verdict(
        on: "Let's update the build script.", original: "Обновляем build script.")
        == .refused(.translated))
  }

  @Test("one English term among Russian words must survive")
  func aSingleEnglishTermIsEnough() {
    #expect(
      RefinementPolicy.verdict(
        on: "Залей билд скрипт в стейджинг.", original: "Залей build script в staging.")
        == .refused(.translated))
  }
}
