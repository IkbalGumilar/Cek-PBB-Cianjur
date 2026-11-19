#include <stdlib.h>

#include "my_application.h"

int main(int argc, char** argv) {
  // Flutter Linux uses GTK3 (FlView / GtkGLArea), which does not implement the
  // Wayland fractional_scale_v1 protocol. On GNOME Wayland with fractional
  // scaling enabled ('scale-monitor-framebuffer'), Mutter assigns buffer_scale=2
  // to the GTK3 window while FlView renders at scale=1 (1366x721 inside a
  // 2732x1442 buffer), causing the entire Flutter viewport to be clipped to the
  // top-left 1/4th of the window with the remaining 3/4ths black.
  // Forcing the X11 (XWayland) GDK backend fixes the viewport scaling cleanly.
  setenv("GDK_BACKEND", "x11", 1);

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
