#include <napi.h>

#ifdef _WIN32
#include <windows.h>

Napi::Value StartDrag(const Napi::CallbackInfo& info) {
  Napi::Env env = info.Env();

  if (!info[0].IsBuffer()) {
    Napi::TypeError::New(env, "Expected buffer as first argument").ThrowAsJavaScriptException();
    return env.Null();
  }

  HWND hwnd = *reinterpret_cast<HWND*>(info[0].As<Napi::Buffer<char>>().Data());

  POINT startPos;
  GetCursorPos(&startPos);
  int startX = startPos.x;
  int startY = startPos.y;

  ScreenToClient(hwnd, &startPos);
  LPARAM lParam = MAKELPARAM(startPos.x, startPos.y);

  ReleaseCapture();
  SendMessage(hwnd, WM_SYSCOMMAND, SC_MOVE | HTCAPTION, 0);

  POINT endPos;
  GetCursorPos(&endPos);
  int endX = endPos.x;
  int endY = endPos.y;

  if (endX == startX && endY == startY) {
    SendMessage(hwnd, WM_LBUTTONUP, 0, lParam);
  }

  return env.Null();
}
#else
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <unistd.h>

Napi::Value StartDrag(const Napi::CallbackInfo& info) {
  Napi::Env env = info.Env();

  Display* display = XOpenDisplay(NULL);
  if (!display) {
    Napi::TypeError::New(env, "Cannot open X display").ThrowAsJavaScriptException();
    return env.Null();
  }

  Window window = (Window)info[0].As<Napi::Number>().Int64Value();

  Window root, child;
  int root_x, root_y, win_x, win_y;
  unsigned int mask;
  XQueryPointer(display, window, &root, &child, &root_x, &root_y, &win_x, &win_y, &mask);

  Atom moveAtom = XInternAtom(display, "_NET_WM_MOVERESIZE", False);
  if (moveAtom == None) {
    XCloseDisplay(display);
    Napi::TypeError::New(env, "Cannot find _NET_WM_MOVERESIZE atom").ThrowAsJavaScriptException();
    return env.Null();
  }

  XEvent xev = {0};
  xev.xclient.type = ClientMessage;
  xev.xclient.window = window;
  xev.xclient.message_type = moveAtom;
  xev.xclient.format = 32;
  xev.xclient.data.l[0] = root_x;
  xev.xclient.data.l[1] = root_y;
  xev.xclient.data.l[2] = 8;
  xev.xclient.data.l[3] = 1;
  xev.xclient.data.l[4] = 0;

  XSendEvent(display, DefaultRootWindow(display), False,
             SubstructureRedirectMask | SubstructureNotifyMask, &xev);
  
  XFlush(display);
  XCloseDisplay(display);

  return env.Null();
}
#endif

Napi::Object Init(Napi::Env env, Napi::Object exports) {
  exports.Set("startDrag", Napi::Function::New(env, StartDrag));
  return exports;
}

NODE_API_MODULE(drag, Init)