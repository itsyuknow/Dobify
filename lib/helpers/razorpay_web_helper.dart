// lib/helpers/razorpay_web_helper.dart
// This file is ONLY imported on web
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

// Store callbacks at module level
Function(String)? _onSuccessCallback;
Function()? _onDismissCallback;
Function(String)? _onErrorCallback;

void setupWebCallbacks({
  required Function(String) onSuccess,
  required Function() onDismiss,
  required Function(String) onError,
}) {
  print('📝 Setting up Razorpay web callbacks');

  // Store callbacks
  _onSuccessCallback = onSuccess;
  _onDismissCallback = onDismiss;
  _onErrorCallback = onError;

  // Setup global handlers that Razorpay will call
  globalContext['razorpaySuccessHandler'] = ((JSAny response) {
    print('🎉 Razorpay success handler called');
    print('📦 Response type: ${response.runtimeType}');

    try {
      String? paymentId;
      String? orderId;
      String? signature;

      // Razorpay returns a JS object, we need to extract properties
      if (response != null) {
        // Try to get all possible fields
        try {
          // Use getProperty to access properties
          paymentId = (response as JSObject).getProperty('razorpay_payment_id'.toJS)?.toString();
          orderId = (response as JSObject).getProperty('razorpay_order_id'.toJS)?.toString();
          signature = (response as JSObject).getProperty('razorpay_signature'.toJS)?.toString();

          print('💳 Payment ID (direct): $paymentId');
          print('🆔 Order ID: $orderId');
          print('🔐 Signature: ${signature?.substring(0, 10)}...');
        } catch (e) {
          print('Direct access failed: $e');
        }

        // Last resort: Convert to string and parse
        if (paymentId == null) {
          try {
            String responseStr = response.toString();
            print('📄 Response string: $responseStr');

            // Try to extract payment ID from string representation
            final match = RegExp(r'razorpay_payment_id["\s:]+([a-zA-Z0-9_]+)').firstMatch(responseStr);
            if (match != null && match.groupCount > 0) {
              paymentId = match.group(1);
              print('💳 Payment ID (regex): $paymentId');
            }
          } catch (e) {
            print('String parsing failed: $e');
          }
        }
      }

      print('💳 Final Payment ID: $paymentId');

      if (paymentId != null && paymentId.isNotEmpty && paymentId != 'null') {
        print('✅ Valid payment ID found, calling callback');
        _onSuccessCallback?.call(paymentId);
        print('✅ Callback executed');
      } else {
        print('⚠️ No valid payment ID found');
        // For COD or testing, you might want to proceed anyway
        // Uncomment the line below if you want to allow orders without payment ID
        // _onSuccessCallback?.call('MANUAL_${DateTime.now().millisecondsSinceEpoch}');
        _onErrorCallback?.call('Payment ID not received from Razorpay');
      }
    } catch (e, stackTrace) {
      print('❌ Error in success handler: $e');
      print('📍 Stack: $stackTrace');
      _onErrorCallback?.call('Error processing payment: ${e.toString()}');
    }
  }).toJS;

  globalContext['razorpayDismissHandler'] = (() {
    print('🚪 Razorpay dismiss handler called');
    try {
      _onDismissCallback?.call();
    } catch (e) {
      print('❌ Error in dismiss handler: $e');
    }
  }).toJS;

  globalContext['razorpayErrorHandler'] = ((JSAny error) {
    print('💥 Razorpay error handler called: $error');
    try {
      final errorMsg = error.toString();
      _onErrorCallback?.call(errorMsg);
    } catch (e) {
      print('❌ Error in error handler: $e');
    }
  }).toJS;

  print('✓ All callbacks registered');
}

void openRazorpayWeb(Map<String, dynamic> options) {
  try {
    print('🌐 Opening Razorpay on Web');
    print('📦 Options keys: ${options.keys.join(', ')}');

    // Check if Razorpay is loaded
    if (!globalContext.has('Razorpay')) {
      throw Exception('Razorpay SDK not loaded. Check index.html');
    }

    // Ensure callbacks are set
    if (!globalContext.has('razorpaySuccessHandler')) {
      throw Exception('Success handler not registered. Call setupWebCallbacks first.');
    }

    print('✅ Razorpay SDK found');
    print('✅ Success handler registered');

    // Create options object with proper handler
    final jsOptions = {
      'key': options['key'],
      'amount': options['amount'],
      'currency': 'INR',
      'order_id': options['order_id'],
      'name': options['name'] ?? 'Dobify',
      'description': options['description'] ?? 'Payment',
      'image': options['image'],
      'prefill': {
        'contact': options['prefill']?['contact'] ?? '',
        'email': options['prefill']?['email'] ?? '',
      },
      'theme': {
        'color': options['theme']?['color'] ?? '#3399cc',
      },
      'modal': {
        'ondismiss': (() {
          print('🚪 Modal dismissed via ondismiss');
          globalContext.callMethod('eval'.toJS, 'window.razorpayDismissHandler()'.toJS);
        }).toJS,
      },
      'handler': globalContext['razorpaySuccessHandler'],
    }.jsify() as JSObject;

    print('🚀 Creating Razorpay instance');
    print('🔑 Key: ${options['key']}');
    print('💰 Amount: ${options['amount']}');
    print('🆔 Order ID: ${options['order_id']}');

    final razorpayClass = globalContext['Razorpay'] as JSFunction;
    final razorpayInstance = razorpayClass.callAsConstructor(jsOptions);

    print('🎬 Opening Razorpay modal');
    (razorpayInstance as JSObject).callMethod('open'.toJS);

    print('✅ Razorpay opened successfully');

  } catch (e, stackTrace) {
    print('❌ openRazorpayWeb error: $e');
    print('📍 Stack: $stackTrace');
    _onErrorCallback?.call('Failed to open payment: ${e.toString()}');
  }
}