// This file is ONLY imported on web
import 'dart:js' as js;
import 'dart:js_util' as jsu;

void openRazorpayWeb(Map<String, dynamic> options) {
  try {
    print('🌐 Opening Razorpay on Web');

    // Convert Map to JS object
    final jsOptions = _convertToJsObject(options);

    // Create Razorpay instance and open
    final razorpayClass = js.context['Razorpay'];
    if (razorpayClass == null) {
      throw Exception('Razorpay is not loaded. Make sure the script is in index.html');
    }

    final rzpInstance = js.JsObject(razorpayClass, [jsOptions]);
    rzpInstance.callMethod('open');

  } catch (e) {
    print('❌ Web Razorpay error: $e');
    rethrow;
  }
}

// Convert Dart Map to proper JS object recursively
dynamic _convertToJsObject(dynamic obj) {
  if (obj is Map) {
    final jsObj = js.JsObject(js.context['Object']);
    obj.forEach((key, value) {
      jsObj[key] = _convertToJsObject(value);
    });
    return jsObj;
  } else if (obj is List) {
    return js.JsArray.from(obj.map(_convertToJsObject));
  } else if (obj is String && obj.startsWith('razorpay')) {
    // This is a function reference, return the actual function
    return js.context[obj];
  }
  return obj;
}

void setupWebCallbacks({
  required Function(String) onSuccess,
  required Function() onDismiss,
  required Function(String) onError,
}) {
  js.context['razorpaySuccessHandler'] = js.allowInterop((dynamic response) {
    try {
      final paymentId = jsu.getProperty(response, 'razorpay_payment_id')?.toString();
      print('✅ Payment success: $paymentId');
      if (paymentId != null && paymentId.isNotEmpty) {
        onSuccess(paymentId);
      }
    } catch (e) {
      print('Error in success handler: $e');
      onError(e.toString());
    }
  });

  js.context['razorpayDismissHandler'] = js.allowInterop(() {
    print('❌ Payment dismissed');
    onDismiss();
  });

  js.context['razorpayError'] = js.allowInterop((dynamic error) {
    print('❌ Razorpay error: $error');
    onError(error.toString());
  });
}