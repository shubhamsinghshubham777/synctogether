#ifndef RUNNER_STORE_PURCHASE_H_
#define RUNNER_STORE_PURCHASE_H_

#include <windows.h>

#include <flutter/binary_messenger.h>

// Microsoft Store subscription purchases (Windows.Services.Store) for the
// Dart `MicrosoftIapService`. Only works in a packaged (MSIX) build that is
// associated with the Store; anywhere else every call answers an error code
// and the Dart side hides the offer.
//
//   products                       -> [{storeId, title, price, currency, period}]
//   purchase {storeId}             -> {status, hresult} (hresult is ExtendedError)
//   idKey {serviceTicket, userId}  -> Store ID key (a JWT) for the server
//
// Store calls block, so they run on a worker thread; results are marshalled
// back to the platform thread with a window message, because MethodResult is
// not thread safe.
void RegisterStorePurchaseChannel(flutter::BinaryMessenger* messenger,
                                  HWND window);

// Posted by worker threads; the window procedure calls this on WM_APP + 0x51.
constexpr UINT kStorePurchaseMessage = WM_APP + 0x51;
void RunStorePurchaseCallbacks();

#endif  // RUNNER_STORE_PURCHASE_H_
