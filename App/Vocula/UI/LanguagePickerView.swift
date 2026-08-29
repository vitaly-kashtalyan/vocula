import SwiftUI
import VoculaKit
import VoculaWhisper

struct LanguagePickerView: View {
  @AppStorage(AppSettings.languageCodesKey)
  private var storedCodes = AppSettings.languageCodesDefault
  @AppStorage(AppSettings.autoDetectLanguageKey)
  private var autoDetect = AppSettings.autoDetectLanguageDefault
  @AppStorage(AppSettings.pinnedLanguageKey)
  private var pinned = AppSettings.pinnedLanguageDefault
  @State private var search = ""

  private var selection: LanguageSelection {
    LanguageSelection(stored: storedCodes, autoDetect: autoDetect, pinned: pinned)
  }

  var body: some View {
    Section {
      Toggle(LanguageScreenCopy.autoDetect, isOn: autoDetectBinding)
        .tint(Theme.accent)
    } footer: {
      VStack(alignment: .leading, spacing: 6) {
        if autoDetect {
          Text(LanguageScreenCopy.detectionExplained)
          Text(LanguageScreenCopy.detectionIsRestricted)
        } else {
          Text(LanguageScreenCopy.noDetection)
        }
        Text(LanguageScreenCopy.qualityVaries)
      }
    }

    Section {
      ForEach(selection.codes, id: \.self) { code in
        LabeledContent {
          HStack(spacing: 10) {
            if !autoDetect {
              Button {
                write(selection.toggling(code))
              } label: {
                Image(
                  systemName: code == selection.pinned
                    ? "largecircle.fill.circle" : "circle")
              }
              .buttonStyle(.borderless)
              .foregroundStyle(
                code == selection.pinned
                  ? Theme.accentText : .secondary
              )
              .accessibilityLabel(Text(LanguageScreenCopy.pinAccessibility(name(of: code))))
              .accessibilityAddTraits(
                code == selection.pinned
                  ? [.isButton, .isSelected] : .isButton
              )
              .help(Text(LanguageScreenCopy.pinHelp))
            }
            Button {
              write(selection.removing(code))
            } label: {
              Image(systemName: "minus.circle.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .disabled(selection.codes.count == 1)
            .accessibilityLabel(Text(LanguageScreenCopy.removeAccessibility(name(of: code))))
            .help(
              selection.codes.count == 1
                ? Text(LanguageScreenCopy.atLeastOne)
                : Text(LanguageScreenCopy.remove))
          }
        } label: {
          label(for: code)
        }
      }
    } header: {
      Text(LanguageScreenCopy.selected)
    } footer: {
      if !autoDetect {
        Text(LanguageScreenCopy.pinnedExplained)
      } else {
        Text(LanguageScreenCopy.cycleExplained)
      }
    }

    Section {
      searchField
      ForEach(matches) { language in
        row(language)
      }
      if matches.isEmpty {
        Text(LanguageScreenCopy.noMatch(search))
          .foregroundStyle(.secondary)
      }
    } header: {
      Text(LanguageScreenCopy.allLanguages)
    } footer: {
      Text(
        verbatim: CountedText.text(
          LanguageCopy.enginesLanguages(count: WhisperLanguages.all.count)))
    }
  }

  private var searchField: some View {
    HStack(spacing: 6) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)
      TextField(LanguageScreenCopy.searchPrompt, text: $search)
        .textFieldStyle(.plain)
        .labelsHidden()
      if !search.isEmpty {
        Button {
          search = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .accessibilityLabel(Text(LanguageScreenCopy.clearSearch))
      }
    }
  }

  private func row(_ language: WhisperLanguage) -> some View {
    SelectableRow(
      isSelected: selection.codes.contains(language.code),
      choose: { write(selection.toggling(language.code)) }
    ) {
      label(for: language.code)
    }
  }

  private func name(of code: String) -> String {
    WhisperLanguages.language(for: code)?.displayName ?? code.uppercased(with: .invariant)
  }

  @ViewBuilder
  private func label(for code: String) -> some View {
    if let language = WhisperLanguages.language(for: code) {
      VStack(alignment: .leading, spacing: 1) {
        Text(verbatim: language.displayName)
        if let native = language.nativeName {
          Text(verbatim: native)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    } else {
      Text(verbatim: code.uppercased(with: .invariant))
    }
  }

  private var autoDetectBinding: Binding<Bool> {
    Binding {
      autoDetect
    } set: {
      write(selection.settingAutoDetect($0))
    }
  }

  private var matches: [WhisperLanguage] {
    let query = search.trimmingCharacters(in: .whitespaces)
    guard !query.isEmpty else { return WhisperLanguages.all }
    return WhisperLanguages.all.filter { language in
      [language.displayName, language.name, language.nativeName ?? "", language.code]
        .contains { $0.localizedStandardContains(query) }
    }
  }

  private func write(_ selection: LanguageSelection) {
    storedCodes = selection.stored
    autoDetect = selection.autoDetect
    pinned = selection.pinned
  }
}
