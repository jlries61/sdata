/* Platform-specific privilege detection for SData.
   Returns 1 when the process is running with elevated system-level privilege
   (root on POSIX, SYSTEM account on Windows), 0 otherwise. */

#ifdef _WIN32
#  include <windows.h>
#  include <shlobj.h>
int sdata_is_system_account (void)
{
    return IsUserAnAdmin () != 0;
}
#else
#  include <unistd.h>
int sdata_is_system_account (void)
{
    return geteuid () == 0;
}
#endif
