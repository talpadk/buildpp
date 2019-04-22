/* The ///#exe comments declares that this file is supposed to result in an executable.
 * it needs to be linked linked with its dependencies
 */
///#exe



//Includes and there for links a static string into the program
#include "my_strings.h"

//Include with <> therefor it isn't expected to be in our sources. eg. it is an external file.
#include <stdio.h>

int main (int argc, char**argv)
{
  printf(helloWorld);
  return 0;
}
