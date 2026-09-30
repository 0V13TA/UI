#include <SDL_main.h>

extern int odin_app_start(void);

int SDL_main(int argc, char **argv)
{
    (void)argc;
    (void)argv;
    return odin_app_start();
}

// Odin's Android runtime references this symbol; SDLActivity owns startup here.
void android_main(void *app)
{
    (void)app;
}
