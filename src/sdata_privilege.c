/* Platform-specific privilege detection for SData.
   Returns 1 when the process is running with elevated system-level privilege
   (root on POSIX, SYSTEM account on Windows), 0 otherwise. */

#ifdef _WIN32
#  include <windows.h>
#  include <string.h>
int sdata_is_system_account (void)
{
    char   name[256];
    DWORD  size = sizeof (name);
    if (!GetUserNameA (name, &size)) return 0;
    return strcmp (name, "SYSTEM") == 0;
}
#else
#  include <unistd.h>
int sdata_is_system_account (void)
{
    return getuid () == 0;
}
#endif
