import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Note: Some keyboards (e.g. certain Samsung or third-party keyboards) may ignore the incognito request, and iOS has no true incognito keyboard API, so on iPhone this reduces learning but cannot be forced.
class PrivateTextField extends StatelessWidget {
  final Key? fieldKey;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;
  final int? maxLines;
  final int? minLines;
  final TextAlign textAlign;
  final TextStyle? style;
  final Color? cursorColor;
  final InputDecoration? decoration;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final bool? enabled;

  const PrivateTextField({
    super.key,
    this.fieldKey,
    this.controller,
    this.focusNode,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.maxLength,
    this.maxLines = 1,
    this.minLines,
    this.textAlign = TextAlign.start,
    this.style,
    this.cursorColor,
    this.decoration,
    this.onSubmitted,
    this.onChanged,
    this.autofocus = false,
    this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: fieldKey,
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      inputFormatters: inputFormatters,
      maxLength: maxLength,
      maxLines: maxLines,
      minLines: minLines,
      textAlign: textAlign,
      style: style,
      cursorColor: cursorColor,
      decoration: decoration,
      onSubmitted: onSubmitted,
      onChanged: onChanged,
      autofocus: autofocus,
      enabled: enabled,
      // Incognito keyboard privacy flags
      enableIMEPersonalizedLearning: false,
      enableSuggestions: false,
      autocorrect: false,
      smartDashesType: SmartDashesType.disabled,
      smartQuotesType: SmartQuotesType.disabled,
      autofillHints: null,
    );
  }
}

