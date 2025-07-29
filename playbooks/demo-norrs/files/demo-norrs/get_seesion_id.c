#include <stdio.h>   // Required for printf()
#include <unistd.h>  // Required for getsid() and pid_t
#include <errno.h>   // Required for errno
#include <string.h>  // Required for strerror()

int main() {
    pid_t session_id;

    // Call getsid() with 0 to get the session ID of the current process
    session_id = getsid(0);

    // Check for errors
    if (session_id == (pid_t)-1) {
        fprintf(stderr, "Error calling getsid(): %s\n", strerror(errno));
        return 1; // Indicate an error
    } else {
        // Print the session ID. pid_t is a signed integer type,
        // casting to long for safe printing with %ld.
        printf("The session ID of the current process is: %ld\n", (long)session_id);
    }

    return 0; // Indicate successful execution
}
