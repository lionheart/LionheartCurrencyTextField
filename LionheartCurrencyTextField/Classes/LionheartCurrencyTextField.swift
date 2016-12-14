//
//  Copyright 2016 Lionheart Software LLC
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import LionheartExtensions

public extension String {
    func charactersInSetBeforeIndex(_ characterSet: CharacterSet, index: Index) -> [UInt16] {
        return substring(to: index).unicodeScalars.filter(characterSet.contains).map { UInt16($0.value) }
    }

    func charactersInSetAfterIndex(_ characterSet: CharacterSet, index: Index) -> [UInt16] {
        return substring(from: index).unicodeScalars.filter(characterSet.contains).map { UInt16($0.value) }
    }

    func charactersInSet(_ characterSet: CharacterSet) -> [UInt16] {
        return unicodeScalars.filter(characterSet.contains).map { UInt16($0.value) }
    }

    func lengthOfRange(_ range: Range<Index>) -> String.IndexDistance {
        return distance(from: range.lowerBound, to: range.upperBound)
    }
}

open class LionheartCurrencyTextField: UITextField, UITextFieldIdentifiable, UITextFieldDelegate {
    open static var identifier = "CurrencyTextFieldIdentifier"

    weak fileprivate var passthroughDelegate: UITextFieldDelegate?
    var decimalPlaces: Int = 2

    static let digitRegularExpression: NSRegularExpression = {
        return try! NSRegularExpression(pattern: "[^\\d\\.]", options: [])
    }()

    static let decimalPointRegularExpression: NSRegularExpression = {
        return try! NSRegularExpression(pattern: "[\\.](\\d+)", options: [])
    }()

    static let digitCharacterSet: CharacterSet = {
        var characterSet = NSMutableCharacterSet.decimalDigit()
        characterSet.addCharacters(in: ".")
        return characterSet as CharacterSet
    }();

    let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        return formatter
    }()

    var locale: Locale? {
        didSet {
            guard let locale = locale else { return }
            currencyFormatter.currencyCode = locale.currencyCode
            currencyFormatter.currencySymbol = locale.currencySymbol
        }
    }

    override open var delegate: UITextFieldDelegate? {
        didSet {
            if delegate !== self {
                passthroughDelegate = delegate
                delegate = self
            }
        }
    }

    convenience init() {
        self.init(locale: Locale.current, decimalPlaces: 2)
    }

    convenience init(locale theLocale: Locale, decimalPlaces: Int) {
        self.init(frame: .zero)

        self.decimalPlaces = decimalPlaces
        locale = theLocale
        delegate = self
    }

    override public init(frame: CGRect) {
        super.init(frame: frame)

        locale = nil
        delegate = self
    }

    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)

        locale = nil
        delegate = self
    }

    // MARK: -

    public var currencyValue: NSDecimalNumber? {
        set {
            text = newValue.flatMap { currencyFormatter.string(from: $0) }
        }

        get {
            guard let text = text, let number = currencyFormatter.number(from: text) else {
                return nil
            }

            return NSDecimalNumber(decimal: number.decimalValue)
        }
    }

    /**
     Breakdown:

     Note: digits encompasses the characters 0-9 and '.'.

     1. Take the current text in the field and replace. ("$12,123.32" -> "$12,123.320")
     2a. If adding digits, count # of digits before insertion point. (A)
     2b. If removing digits, count # of digits after insertion point. (B)
     3. Remove all non-digits. ("$12,123.320" -> "12123.320")
     4. Calculate number of digits after decimal point and multiply * 10^(this value).
     5. Format as currency ("121233.20" -> "$121,233.20")
     6. Find index after traversing A digits. Move selection point to this value.
     */
    func shouldChangeCharactersInRange(_ currentText: String, range: Range<String.Index>, replacementString string: String) -> Bool {
        // These two are re-used a few times, so we assign them to shorter variables.
        let characterSet = LionheartCurrencyTextField.digitCharacterSet
        let digitExpression = LionheartCurrencyTextField.digitRegularExpression

        // Remove all non-digits or periods from the replacement string.
        let string = digitExpression.stringByReplacingMatches(in: string, options: [], range: string.range, withTemplate: "")

        let wasTextDeleted = string.length < string.lengthOfRange(range)
        let numDigits: Int
        if currentText.length > 0 {
            if wasTextDeleted {
                numDigits = currentText.charactersInSetAfterIndex(characterSet, index: string.characters.index(after: range.lowerBound)).count
            } else {
                let numDigitsInEnteredString = string.charactersInSet(CharacterSet.decimalDigits).count
                numDigits = currentText.charactersInSetBeforeIndex(characterSet, index: range.lowerBound).count + numDigitsInEnteredString
            }
        } else {
            numDigits = 1
        }

        // If characters are removed, edit the range to make sure to ignore any non-digits (e.g., ',').
        var range = range
        if wasTextDeleted {
            let length = string.lengthOfRange(range)
            while currentText.substring(with: range).charactersInSet(CharacterSet.decimalDigits).count < length {
                if range.lowerBound == currentText.startIndex {
                    break
                }

                let startIndex = string.characters.index(before: range.lowerBound)
                range = startIndex..<range.upperBound
            }
        }

        var replacedText = currentText.replacingCharacters(in: range, with: string)
        if replacedText == "" {
            return true
        }

        replacedText = digitExpression.stringByReplacingMatches(in: replacedText, options: [], range: replacedText.range, withTemplate: "")

        var number = NSDecimalNumber(string: replacedText)
        // MARK: ???
        if number == NSDecimalNumber.notANumber {
            // If the new text can't be parsed, only let the user edit if characters are being removed.
            return wasTextDeleted
        }

        if let match = LionheartCurrencyTextField.decimalPointRegularExpression.firstMatch(in: replacedText, options: [], range: replacedText.range) {
            let numbersAfterDecimal = match.range.length - 1
            currencyFormatter.minimumFractionDigits = min(decimalPlaces, numbersAfterDecimal)

            // If there are more than N digits after the decimal point, move the decimal place.
            if numbersAfterDecimal > decimalPlaces {
                number = number.multiplying(byPowerOf10: Int16(numbersAfterDecimal) - decimalPlaces)
            }
        } else {
            currencyFormatter.minimumFractionDigits = 0
        }

        // If the text can't be formatted as currency, just let the user edit it.
        guard var formattedText = currencyFormatter.string(from: number) else {
            return true
        }

        // If the added string is a '.', add it. Otherwise, the above logic will prevent us from ever entering a decimal.
        if string == "." {
            formattedText += "."
        }

        text = formattedText

        // Once the new text is set, update the cursor position to the correct location. We do this by maintaining the cursor's place in terms of number of digits from the beginning, or number of digits from the end (depending on whether text has been removed or added).
        var numCharactersEncountered = 0

        // This variable is used as a tally to match against the original number of digits preceding or following the original cursor position.
        var numDigitsEncountered = 0
        let characters: [UTF16.CodeUnit]

        if wasTextDeleted {
            // If text is deleted, we want to count characters going backwards.
            characters = formattedText.utf16.reversed()
        } else {
            characters = formattedText.utf16.map { $0 }
        }

        for character in characters {
            if numDigitsEncountered > numDigits {
                break
            }

            if characterSet.contains(UnicodeScalar(character)!) {
                numDigitsEncountered += 1
            }

            numCharactersEncountered += 1
        }

        let _start: UITextPosition?
        if wasTextDeleted {
            _start = position(from: endOfDocument, offset: -numCharactersEncountered+string.lengthOfRange(range))
        } else {
            _start = position(from: beginningOfDocument, offset: numCharactersEncountered)
        }

        guard let start = _start,
            let end = position(from: start, offset: 0) else {
                return false
        }

        // If we have a valid start and end position, we set the selected text range.
        selectedTextRange = textRange(from: start, to: end)
        return false
    }

    open func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if !(passthroughDelegate?.textField?(textField, shouldChangeCharactersIn: range, replacementString: string) ?? true) {
            return false
        }

        guard let _text = text else {
            return true
        }

        let range = _text.toRange(range)
        return shouldChangeCharactersInRange(_text, range: range, replacementString: string)
    }

    // MARK: - Default UITextFieldDelegate Implementation

    open func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        return passthroughDelegate?.textFieldShouldEndEditing?(textField) ?? true
    }

    open func textFieldDidBeginEditing(_ textField: UITextField) {
        passthroughDelegate?.textFieldDidBeginEditing?(textField)
    }

    open func textFieldShouldEndEditing(_ textField: UITextField) -> Bool {
        return passthroughDelegate?.textFieldShouldEndEditing?(textField) ?? true
    }

    open func textFieldDidEndEditing(_ textField: UITextField) {
        passthroughDelegate?.textFieldDidEndEditing?(textField)

        guard let _text = text else {
            return
        }

        let range = _text.range
        let replacedText = LionheartCurrencyTextField.digitRegularExpression.stringByReplacingMatches(in: _text, options: [], range: range, withTemplate: "")
        let value = NSDecimalNumber(string: replacedText)

        currencyFormatter.minimumFractionDigits = decimalPlaces
        text = currencyFormatter.string(from: value)
    }
    
    open func textFieldShouldClear(_ textField: UITextField) -> Bool {
        return passthroughDelegate?.textFieldShouldClear?(textField) ?? true
    }
    
    open func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        return passthroughDelegate?.textFieldShouldReturn?(textField) ?? true
    }
}
