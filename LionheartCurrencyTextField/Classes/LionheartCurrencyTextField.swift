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

extension String {
    func charactersInSetBeforeIndex(characterSet: NSCharacterSet, index: Index) -> [UInt16] {
        return substringToIndex(index).utf16.filter(characterSet.characterIsMember)
    }

    func charactersInSetAfterIndex(characterSet: NSCharacterSet, index: Index) -> [UInt16] {
        return substringFromIndex(index).utf16.filter(characterSet.characterIsMember)
    }

    func charactersInSet(characterSet: NSCharacterSet) -> [UInt16] {
        return utf16.filter(characterSet.characterIsMember)
    }
}

extension Range where Element: BidirectionalIndexType {
    var length: Element.Distance {
        return startIndex.distanceTo(endIndex)
    }
}

class LionheartCurrencyTextField: UITextField, UITextFieldIdentifiable, UITextFieldDelegate {
    static var identifier = "CurrencyTextFieldIdentifier"

    weak private var passthroughDelegate: UITextFieldDelegate?

    static let digitRegularExpression: NSRegularExpression = {
        return try! NSRegularExpression(pattern: "[^\\d\\.]", options: [])
    }()

    static let decimalPointRegularExpression: NSRegularExpression = {
        return try! NSRegularExpression(pattern: "[\\.](\\d+)", options: [])
    }()

    static let digitCharacterSet: NSCharacterSet = {
        var characterSet = NSMutableCharacterSet.decimalDigitCharacterSet()
        characterSet.addCharactersInString(".")
        return characterSet
    }();

    let currencyFormatter: NSNumberFormatter = {
        let formatter = NSNumberFormatter()
        formatter.numberStyle = .CurrencyStyle
        return formatter
    }()

    var locale: NSLocale? {
        didSet {
            guard let locale = locale else { return }

            currencyFormatter.currencyCode = locale.objectForKey(NSLocaleCurrencyCode) as? String
            currencyFormatter.currencySymbol = locale.objectForKey(NSLocaleCurrencySymbol) as? String
        }
    }

    override var delegate: UITextFieldDelegate? {
        didSet {
            if delegate !== self {
                passthroughDelegate = delegate
                delegate = self
            }
        }
    }

    convenience init() {
        self.init(locale: NSLocale.currentLocale())
    }

    convenience init(locale theLocale: NSLocale) {
        self.init(frame: .zero)

        locale = theLocale
        delegate = self
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    // MARK: -

    var currencyValue: NSDecimalNumber? {
        set {
            text = newValue.flatMap { currencyFormatter.stringFromNumber($0) }
        }

        get {
            return NSDecimalNumber(string: text)
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
    func shouldChangeCharactersInRange(currentText: String, range: Range<String.Index>, replacementString string: String) -> Bool {
        // These two are re-used a few times, so we assign them to shorter variables.
        let characterSet = LionheartCurrencyTextField.digitCharacterSet
        let digitExpression = LionheartCurrencyTextField.digitRegularExpression

        // Remove all non-digits or periods from the replacement string.
        let string = digitExpression.stringByReplacingMatchesInString(string, options: [], range: string.range(), withTemplate: "")

        let wasTextDeleted = string.length < range.length
        let numDigits: Int
        if currentText.length > 0 {
            if wasTextDeleted {
                numDigits = currentText.charactersInSetAfterIndex(characterSet, index: range.startIndex.advancedBy(1)).count
            } else {
                let numDigitsInEnteredString = string.charactersInSet(NSCharacterSet.decimalDigitCharacterSet()).count
                numDigits = currentText.charactersInSetBeforeIndex(characterSet, index: range.startIndex).count + numDigitsInEnteredString
            }
        } else {
            numDigits = 1
        }

        // If characters are removed, edit the range to make sure to ignore any non-digits (e.g., ',').
        var range = range
        if wasTextDeleted {
            let length = range.length
            while currentText.substringWithRange(range).charactersInSet(NSCharacterSet.decimalDigitCharacterSet()).count < length {
                if range.startIndex == currentText.startIndex {
                    break
                }

                let startIndex = range.startIndex.predecessor()
                range = startIndex..<range.endIndex
            }
        }

        var replacedText = currentText.stringByReplacingCharactersInRange(range, withString: string)
        if replacedText == "" {
            return true
        }

        replacedText = digitExpression.stringByReplacingMatchesInString(replacedText, options: [], range: replacedText.range(), withTemplate: "")

        var number = NSDecimalNumber(string: replacedText)
        if number.isNaN() {
            // If the new text can't be parsed, only let the user edit if characters are being removed.
            return wasTextDeleted
        }

        if let match = LionheartCurrencyTextField.decimalPointRegularExpression.firstMatchInString(replacedText, options: [], range: replacedText.range()) {
            let numbersAfterDecimal = match.range.length - 1
            currencyFormatter.minimumFractionDigits = min(2, numbersAfterDecimal)

            // If there are more than two digits after the decimal point, move the decimal place.
            // MARK: TODO Make this configurable.
            if numbersAfterDecimal > 2 {
                number = number.decimalNumberByMultiplyingByPowerOf10(Int16(numbersAfterDecimal) - 2)
            }
        } else {
            currencyFormatter.minimumFractionDigits = 0
        }

        // If the text can't be formatted as currency, just let the user edit it.
        guard var formattedText = currencyFormatter.stringFromNumber(number) else {
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
            characters = formattedText.utf16.reverse()
        } else {
            characters = formattedText.utf16.map { $0 }
        }

        for character in characters {
            if numDigitsEncountered > numDigits {
                break
            }

            if characterSet.characterIsMember(character) {
                numDigitsEncountered += 1
            }

            numCharactersEncountered += 1
        }

        let _start: UITextPosition?
        if wasTextDeleted {
            _start = positionFromPosition(endOfDocument, offset: -numCharactersEncountered+range.length)
        } else {
            _start = positionFromPosition(beginningOfDocument, offset: numCharactersEncountered)
        }

        guard let start = _start,
            let end = positionFromPosition(start, offset: 0) else {
                return false
        }

        // If we have a valid start and end position, we set the selected text range.
        selectedTextRange = textRangeFromPosition(start, toPosition: end)
        return false
    }

    func textField(textField: UITextField, shouldChangeCharactersInRange range: NSRange, replacementString string: String) -> Bool {
        if !(passthroughDelegate?.textField?(textField, shouldChangeCharactersInRange: range, replacementString: string) ?? true) {
            return false
        }

        guard let _text = text else {
            return true
        }

        let range = _text.toRange(range)
        return shouldChangeCharactersInRange(_text, range: range, replacementString: string)
    }

    // MARK: - Default UITextFieldDelegate Implementation

    func textFieldShouldBeginEditing(textField: UITextField) -> Bool {
        return passthroughDelegate?.textFieldShouldEndEditing?(textField) ?? true
    }

    func textFieldDidBeginEditing(textField: UITextField) {
        passthroughDelegate?.textFieldDidBeginEditing?(textField)
    }

    func textFieldShouldEndEditing(textField: UITextField) -> Bool {
        return passthroughDelegate?.textFieldShouldEndEditing?(textField) ?? true
    }

    func textFieldDidEndEditing(textField: UITextField) {
        passthroughDelegate?.textFieldDidEndEditing?(textField)

        guard let _text = text else {
            return
        }

        let range = _text.range()
        let replacedText = LionheartCurrencyTextField.digitRegularExpression.stringByReplacingMatchesInString(_text, options: [], range: range, withTemplate: "")
        let value = NSDecimalNumber(string: replacedText)

        text = currencyFormatter.stringFromNumber(value)
    }
    
    func textFieldShouldClear(textField: UITextField) -> Bool {
        return passthroughDelegate?.textFieldShouldClear?(textField) ?? true
    }
    
    func textFieldShouldReturn(textField: UITextField) -> Bool {
        return passthroughDelegate?.textFieldShouldReturn?(textField) ?? true
    }
}