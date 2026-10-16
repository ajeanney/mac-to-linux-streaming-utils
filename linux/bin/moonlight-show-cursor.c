/*
 * LD_PRELOAD shim for Moonlight: keep the local Linux cursor visible.
 *
 * Moonlight hides the cursor with SDL_ShowCursor(SDL_DISABLE) whenever it
 * captures the mouse, and the Ctrl+Alt+Shift+C toggle that undoes it is
 * state-dependent and easy to miss at startup. Forcing SDL_ShowCursor to
 * always enable makes the real cursor show on every stream window, reliably.
 */
#define _GNU_SOURCE
#include <dlfcn.h>

int SDL_ShowCursor(int toggle)
{
    static int (*real)(int);
    if (!real) real = (int (*)(int))dlsym(RTLD_NEXT, "SDL_ShowCursor");
    if (real) real(1);
    return 1;
}
