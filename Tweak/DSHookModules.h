#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

void DSInitLSDOpenClientHooks(Class lsdOpenClientClass);
void DSInitLSWorkspaceHooks(Class lsWorkspaceClass);
void DSInitSourceUIApplicationHooks(Class applicationClass);
void DSInitLSAppLinkHooks(Class lsAppLinkClass);
void DSInitSpringBoardHooks(Class mainWorkspaceClass, Class springBoardClass);

#ifdef __cplusplus
}
#endif
