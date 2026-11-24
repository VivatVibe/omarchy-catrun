import QtQuick

// Plain-text wrapper enforcing Text.PlainText so dynamic strings can never be
// parsed as Qt rich text (AutoText).
Text {
  textFormat: Text.PlainText
}
