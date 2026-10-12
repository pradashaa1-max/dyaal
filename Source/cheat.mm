// Astral Cheat dylib v3.1 — inject into StandRise (same process = menu over game)
// GitHub Actions builds .dylib; optional workflow packs into game IPA
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#include <cmath>
#include <vector>
#include <string>
#include <mutex>
#include <algorithm>
#include <cstdint>

#define CFG_DIR @"AstralCheats"

static BOOL gReady=NO, gMenu=NO;
static int gTab=0, gLang=0;
static float gAR=0.25f,gAG=0.55f,gAB=1.f;
static BOOL gAim=YES,gSilent=YES,gFovDraw=YES;
static float gFov=15.f;
static BOOL gEsp=YES,gBox=YES,gName=YES,gHP=YES,gDist=YES,gSnap=NO,gTeam=YES;
static BOOL gHideRec=YES;
static NSString*gCfgName=@"default";

struct V3{float x,y,z; V3(float a=0,float b=0,float c=0):x(a),y(b),z(c){}
    V3 operator-(const V3&o)const{return {x-o.x,y-o.y,z-o.z};}
    float len()const{return sqrtf(x*x+y*y+z*z);}
    V3 norm()const{float l=len();return l>1e-6f?V3{x/l,y/l,z/l}:V3{};}
};
struct V2{float x,y;};
struct M4{float m[16]{};};
struct Ent{V3 pos,head;float hp,maxHp,dist;int team;bool local,dead;std::string name;};
static std::vector<Ent> gEnts; static std::mutex gMtx;
static V3 gLocal; static int gLocalTeam=-1; static M4 gVM;
static bool gHasVM=false;

// ----- UPDATE THESE from dump.cs -----
namespace Off {
    const uint32_t Health=0x48, MaxHP=0x4C, Team=0x5C, Dead=0x60;
    const uint32_t Transform=0x30, AimPitch=0x40, AimYaw=0x44;
}
// -------------------------------------

static bool W2S(const V3&w,V2&o,float sw,float sh){
    if(!gHasVM)return false;
    const float*m=gVM.m; float cw=m[3]*w.x+m[7]*w.y+m[11]*w.z+m[15];
    if(cw<0.01f)return false; float inv=1.f/cw;
    o.x=(sw*0.5f)*(1.f+(m[0]*w.x+m[4]*w.y+m[8]*w.z+m[12])*inv);
    o.y=(sh*0.5f)*(1.f-(m[1]*w.x+m[5]*w.y+m[9]*w.z+m[13])*inv);
    return true;
}

static NSString*T(NSString*ru,NSString*en){return gLang==0?ru:en;}

static NSString*CfgRoot(){
    NSString*d=[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject stringByAppendingPathComponent:CFG_DIR];
    [[NSFileManager defaultManager]createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:nil];
    return d;
}
static NSDictionary*CfgDict(){
    return @{@"aim":@(gAim),@"silent":@(gSilent),@"fovDraw":@(gFovDraw),@"fov":@(gFov),
        @"esp":@(gEsp),@"box":@(gBox),@"name":@(gName),@"hp":@(gHP),@"dist":@(gDist),@"snap":@(gSnap),@"team":@(gTeam),
        @"hideRec":@(gHideRec),@"lang":@(gLang),@"ar":@(gAR),@"ag":@(gAG),@"ab":@(gAB)};
}
static void ApplyCfg(NSDictionary*d){
    if(![d isKindOfClass:[NSDictionary class]])return;
    gAim=[d[@"aim"]boolValue];gSilent=[d[@"silent"]boolValue];gFovDraw=[d[@"fovDraw"]boolValue];
    gFov=fmaxf(1,fminf(30,[d[@"fov"]floatValue]));
    gEsp=[d[@"esp"]boolValue];gBox=[d[@"box"]boolValue];gName=[d[@"name"]boolValue];
    gHP=[d[@"hp"]boolValue];gDist=[d[@"dist"]boolValue];gSnap=[d[@"snap"]boolValue];gTeam=[d[@"team"]boolValue];
    gHideRec=[d[@"hideRec"]boolValue];gLang=[d[@"lang"]intValue];
    if(d[@"ar"]){gAR=[d[@"ar"]floatValue];gAG=[d[@"ag"]floatValue];gAB=[d[@"ab"]floatValue];}
}
static void SaveCfgNamed(NSString*n){
    if(!n.length)n=@"default"; gCfgName=n;
    NSString*p=[[CfgRoot() stringByAppendingPathComponent:n] stringByAppendingPathExtension:@"json"];
    [[NSJSONSerialization dataWithJSONObject:CfgDict() options:NSJSONWritingPrettyPrinted error:nil] writeToFile:p atomically:YES];
}
static void LoadCfgNamed(NSString*n){
    NSString*p=[[CfgRoot() stringByAppendingPathComponent:n] stringByAppendingPathExtension:@"json"];
    NSData*data=[NSData dataWithContentsOfFile:p]; if(!data)return;
    ApplyCfg([NSJSONSerialization JSONObjectWithData:data options:0 error:nil]); gCfgName=n;
}
static NSArray*ListCfgs(){
    NSMutableArray*a=[NSMutableArray array];
    for(NSString*f in [[NSFileManager defaultManager]contentsOfDirectoryAtPath:CfgRoot() error:nil])
        if([f hasSuffix:@".json"])[a addObject:[f stringByDeletingPathExtension]];
    return a;
}

// Il2Cpp best-effort (works only when injected into Unity game)
static void*(*il2cpp_domain_get)()=nullptr;
static void*(*il2cpp_thread_attach)(void*)=nullptr;
static void ResolveIL(){
    static bool once=false; if(once)return; once=true;
    il2cpp_domain_get=(decltype(il2cpp_domain_get))dlsym(RTLD_DEFAULT,"il2cpp_domain_get");
    il2cpp_thread_attach=(decltype(il2cpp_thread_attach))dlsym(RTLD_DEFAULT,"il2cpp_thread_attach");
    if(il2cpp_domain_get&&il2cpp_thread_attach){
        void*d=il2cpp_domain_get();
        if(d) il2cpp_thread_attach(d);
        NSLog(@"[Astral] il2cpp attached");
    } else NSLog(@"[Astral] il2cpp symbols missing (not in game process?)");
}

// Fill entities — expand when you have dump.cs field offsets + object list
static void GameTick(){
    ResolveIL();
    // Placeholder: keeps structure for real player walk from PlayerManager
    // When offsets known: read array of PlayerController*, fill gEnts, gLocal, gVM from Camera
}

// Reliable hide from screenshot / screen recording (secureTextEntry container)
static UITextField*gSecureField=nil;
static UIView*gSecureContainer=nil;

static void ApplyCaptureHide(UIWindow*win, UIView*content, BOOL hide){
    if(!win||!content)return;
    if(hide){
        if(!gSecureField){
            gSecureField=[[UITextField alloc] initWithFrame:win.bounds];
            gSecureField.secureTextEntry=YES;
            gSecureField.userInteractionEnabled=NO;
            gSecureField.backgroundColor=UIColor.clearColor;
        }
        gSecureField.frame=win.bounds;
        if(gSecureField.superview!=win) [win addSubview:gSecureField];
        // iOS puts secure content in a special view inside the text field
        UIView*sec=nil;
        for(UIView*v in gSecureField.subviews){
            if(v.subviews.count||v.layer.sublayers.count){sec=v;break;}
        }
        if(!sec && gSecureField.subviews.count) sec=gSecureField.subviews.firstObject;
        if(sec){
            gSecureContainer=sec;
            if(content.superview!=sec){
                [content removeFromSuperview];
                content.frame=sec.bounds;
                content.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
                [sec addSubview:content];
            }
            sec.userInteractionEnabled=YES;
        } else {
            // fallback private API
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            SEL s=NSSelectorFromString(@"_setSecure:");
            if([win respondsToSelector:s]) ((void(*)(id,SEL,BOOL))objc_msgSend)(win,s,YES);
            if([content respondsToSelector:s]) ((void(*)(id,SEL,BOOL))objc_msgSend)(content,s,YES);
#pragma clang diagnostic pop
        }
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        SEL s=NSSelectorFromString(@"_setSecure:");
        if([win respondsToSelector:s]) ((void(*)(id,SEL,BOOL))objc_msgSend)(win,s,NO);
#pragma clang diagnostic pop
        if(content.superview!=win.rootViewController.view){
            [content removeFromSuperview];
            content.frame=win.bounds;
            [win.rootViewController.view addSubview:content];
        }
    }
}

@interface ACW:UIWindow @end
@implementation ACW
- (BOOL)_isSecure{return gHideRec;}
- (BOOL)isSecure{return gHideRec;}
- (BOOL)_shouldCreateContextAsSecure{return gHideRec;}
@end

@interface ACH:UIView
@property(nonatomic,strong)CADisplayLink*link;
@property(nonatomic,strong)UIView*fab,*panel,*side;
@property(nonatomic,strong)UIScrollView*scroll;
- (void)rebuild;
@end
static ACW*gWin; static ACH*gHud;

@implementation ACH
- (instancetype)initWithFrame:(CGRect)f{
    self=[super initWithFrame:f]; if(!self)return nil;
    self.backgroundColor=UIColor.clearColor; self.userInteractionEnabled=YES;
    CGFloat S=52;
    self.fab=[[UIView alloc]initWithFrame:CGRectMake(f.size.width-S-14,f.size.height*0.5,S,S)];
    self.fab.backgroundColor=[UIColor colorWithRed:0.08 green:0.15 blue:0.3 alpha:0.95];
    self.fab.layer.cornerRadius=S/2; self.fab.layer.borderWidth=2;
    self.fab.layer.borderColor=[UIColor colorWithRed:gAR green:gAG blue:gAB alpha:1].CGColor;
    UILabel*fl=[[UILabel alloc]initWithFrame:self.fab.bounds];
    fl.text=@"A"; fl.textAlignment=NSTextAlignmentCenter;
    fl.font=[UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    fl.textColor=[UIColor colorWithRed:0.55 green:0.85 blue:1 alpha:1];
    [self.fab addSubview:fl];
    [self.fab addGestureRecognizer:[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(fabTap)]];
    [self.fab addGestureRecognizer:[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(fabPan:)]];
    [self addSubview:self.fab];

    CGFloat pw=fminf(f.size.width-20,520), ph=fminf(f.size.height-70,360);
    self.panel=[[UIView alloc]initWithFrame:CGRectMake((f.size.width-pw)/2,(f.size.height-ph)/2,pw,ph)];
    self.panel.backgroundColor=[UIColor colorWithRed:0.04 green:0.07 blue:0.12 alpha:0.97];
    self.panel.layer.cornerRadius=18;
    self.panel.layer.borderWidth=1;
    self.panel.layer.borderColor=[UIColor colorWithRed:gAR green:gAG blue:gAB alpha:0.45].CGColor;
    self.panel.hidden=YES; [self addSubview:self.panel];

    CGFloat sw=130;
    self.side=[[UIView alloc]initWithFrame:CGRectMake(0,0,sw,ph)];
    self.side.backgroundColor=[UIColor colorWithRed:0.03 green:0.05 blue:0.1 alpha:1];
    [self.panel addSubview:self.side];
    UILabel*lg=[[UILabel alloc]initWithFrame:CGRectMake(8,14,sw-16,36)];
    lg.text=@"ASTRAL"; lg.textAlignment=NSTextAlignmentCenter;
    lg.font=[UIFont systemFontOfSize:15 weight:UIFontWeightBlack];
    lg.textColor=[UIColor colorWithRed:0.4 green:0.75 blue:1 alpha:1]; [self.side addSubview:lg];
    for(int i=0;i<4;i++){
        UIButton*b=[UIButton buttonWithType:UIButtonTypeSystem];
        b.frame=CGRectMake(8,60+i*44,sw-16,38); b.tag=100+i; b.layer.cornerRadius=10;
        [b addTarget:self action:@selector(tab:) forControlEvents:UIControlEventTouchUpInside];
        [self.side addSubview:b];
    }
    UIButton*lang=[UIButton buttonWithType:UIButtonTypeSystem];
    lang.frame=CGRectMake(8,ph-48,sw-16,32); lang.tag=200;
    [lang addTarget:self action:@selector(togLang) forControlEvents:UIControlEventTouchUpInside];
    [self.side addSubview:lang];

    self.scroll=[[UIScrollView alloc]initWithFrame:CGRectMake(sw,0,pw-sw,ph)];
    self.scroll.alwaysBounceVertical=YES; [self.panel addSubview:self.scroll];
    [self.side addGestureRecognizer:[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(panPanel:)]];
    [self rebuild]; return self;
}
- (void)relabel{
    NSArray*ru=@[@"Прицел",@"Визуалы",@"Разное",@"Конфиг"];
    NSArray*en=@[@"Aim",@"Visuals",@"Misc",@"Config"];
    for(int i=0;i<4;i++){
        UIButton*b=(UIButton*)[self.side viewWithTag:100+i];
        [b setTitle:(gLang==0?ru[i]:en[i]) forState:UIControlStateNormal];
        BOOL on=gTab==i;
        [b setTitleColor:on?UIColor.whiteColor:[UIColor colorWithWhite:0.5 alpha:1] forState:UIControlStateNormal];
        b.backgroundColor=on?[UIColor colorWithRed:gAR green:gAG blue:gAB alpha:0.35]:UIColor.clearColor;
        b.titleLabel.font=[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    }
    UIButton*l=(UIButton*)[self.side viewWithTag:200];
    [l setTitle:(gLang==0?@"RU | EN":@"EN | RU") forState:UIControlStateNormal];
    [l setTitleColor:[UIColor colorWithWhite:0.55 alpha:1] forState:UIControlStateNormal];
}
- (void)card:(NSString*)title sub:(NSString*)sub y:(CGFloat)y tag:(int)tag on:(BOOL)on sl:(BOOL)sl{
    CGFloat w=self.scroll.bounds.size.width>20?self.scroll.bounds.size.width-24:360;
    UIView*c=[[UIView alloc]initWithFrame:CGRectMake(12,y,w,sl?90:66)];
    c.backgroundColor=[UIColor colorWithRed:0.06 green:0.1 blue:0.18 alpha:1];
    c.layer.cornerRadius=14; c.layer.borderWidth=1;
    c.layer.borderColor=[UIColor colorWithRed:gAR green:gAG blue:gAB alpha:0.25].CGColor;
    c.tag=tag;
    UILabel*t=[[UILabel alloc]initWithFrame:CGRectMake(14,10,w-80,22)];
    t.text=title; t.font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold]; t.textColor=UIColor.whiteColor; [c addSubview:t];
    UILabel*s=[[UILabel alloc]initWithFrame:CGRectMake(14,32,w-80,18)];
    s.text=sub; s.font=[UIFont systemFontOfSize:11]; s.textColor=[UIColor colorWithWhite:0.5 alpha:1]; [c addSubview:s];
    UISwitch*sw=[[UISwitch alloc]initWithFrame:CGRectZero]; sw.on=on; sw.tag=1; sw.onTintColor=[UIColor colorWithRed:gAR green:gAG blue:gAB alpha:1];
    sw.center=CGPointMake(w-42,32);
    [sw addTarget:self action:@selector(onSw:) forControlEvents:UIControlEventValueChanged]; [c addSubview:sw];
    if(sl){
        UISlider*slid=[[UISlider alloc]initWithFrame:CGRectMake(14,58,w-100,24)];
        slid.minimumValue=1; slid.maximumValue=30; slid.value=gFov; slid.tag=2;
        slid.minimumTrackTintColor=[UIColor colorWithRed:gAR green:gAG blue:gAB alpha:1];
        [slid addTarget:self action:@selector(onFov:) forControlEvents:UIControlEventValueChanged]; [c addSubview:slid];
        UILabel*lv=[[UILabel alloc]initWithFrame:CGRectMake(w-80,58,66,24)]; lv.tag=3;
        lv.textAlignment=NSTextAlignmentRight; lv.font=[UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        lv.textColor=[UIColor colorWithWhite:0.7 alpha:1];
        lv.text=[NSString stringWithFormat:@"%.0f | 1-30",gFov]; [c addSubview:lv];
    }
    [self.scroll addSubview:c];
}
- (void)rebuild{
    for(UIView*v in [self.scroll.subviews copy])[v removeFromSuperview];
    CGFloat y=12;
    if(gTab==0){
        [self card:T(@"Аимбот",@"Aim bot") sub:T(@"Автоприцел",@"Auto aim") y:y tag:10 on:gAim sl:NO]; y+=78;
        [self card:T(@"Круг FOV",@"FOV Circle") sub:T(@"Круг 1–30",@"Circle 1-30") y:y tag:11 on:gFovDraw sl:YES]; y+=102;
        [self card:T(@"Сайлент",@"Silent") sub:T(@"Скрытый аим",@"Silent aim") y:y tag:12 on:gSilent sl:NO]; y+=78;
    }else if(gTab==1){
        [self card:@"ESP" sub:T(@"Визуалы",@"Visuals") y:y tag:20 on:gEsp sl:NO]; y+=78;
        [self card:T(@"Бокс",@"Box") sub:@"" y:y tag:21 on:gBox sl:NO]; y+=78;
        [self card:T(@"Имя",@"Name") sub:@"" y:y tag:22 on:gName sl:NO]; y+=78;
        [self card:T(@"ХП",@"HP") sub:@"" y:y tag:23 on:gHP sl:NO]; y+=78;
        [self card:T(@"Дистанция",@"Distance") sub:@"" y:y tag:24 on:gDist sl:NO]; y+=78;
        [self card:T(@"Линии",@"Snaplines") sub:@"" y:y tag:25 on:gSnap sl:NO]; y+=78;
        [self card:T(@"Тимчек",@"Team check") sub:@"" y:y tag:26 on:gTeam sl:NO]; y+=78;
    }else if(gTab==2){
        [self card:T(@"Скрыть запись",@"Hide Recording") sub:T(@"Не видно на скрине/видео",@"Hide from capture") y:y tag:30 on:gHideRec sl:NO]; y+=78;
        UILabel*cl=[[UILabel alloc]initWithFrame:CGRectMake(16,y,200,20)];
        cl.text=T(@"Цвет меню",@"Menu color"); cl.textColor=[UIColor colorWithWhite:0.65 alpha:1];
        cl.font=[UIFont systemFontOfSize:13 weight:UIFontWeightMedium]; [self.scroll addSubview:cl]; y+=28;
        NSArray*cols=@[@[@0.25f,@0.55f,@1.f],@[@0.6f,@0.2f,@1.f],@[@0.1f,@0.85f,@0.5f],@[@1.f,@0.35f,@0.2f],@[@1.f,@0.2f,@0.45f]];
        for(int i=0;i<5;i++){ UIButton*b=[UIButton buttonWithType:UIButtonTypeCustom];
            b.frame=CGRectMake(16+i*52,y,40,40); b.layer.cornerRadius=20; b.tag=300+i;
            b.backgroundColor=[UIColor colorWithRed:[cols[i][0]floatValue] green:[cols[i][1]floatValue] blue:[cols[i][2]floatValue] alpha:1];
            [b addTarget:self action:@selector(col:) forControlEvents:UIControlEventTouchUpInside]; [self.scroll addSubview:b]; }
        y+=56;
    }else{
        UILabel*cur=[[UILabel alloc]initWithFrame:CGRectMake(16,y,300,20)];
        cur.text=[NSString stringWithFormat:@"%@: %@",T(@"Текущий",@"Current"),gCfgName];
        cur.textColor=[UIColor colorWithWhite:0.65 alpha:1]; [self.scroll addSubview:cur]; y+=28;
        UIButton*save=[UIButton buttonWithType:UIButtonTypeSystem];
        save.frame=CGRectMake(12,y,(self.scroll.bounds.size.width-32)/2,40);
        [save setTitle:T(@"Сохранить",@"Save") forState:UIControlStateNormal];
        [save setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        save.backgroundColor=[UIColor colorWithRed:gAR green:gAG blue:gAB alpha:0.5]; save.layer.cornerRadius=12;
        [save addTarget:self action:@selector(save) forControlEvents:UIControlEventTouchUpInside]; [self.scroll addSubview:save];
        UIButton*share=[UIButton buttonWithType:UIButtonTypeSystem];
        share.frame=CGRectMake(16+(self.scroll.bounds.size.width-32)/2,y,(self.scroll.bounds.size.width-32)/2,40);
        [share setTitle:T(@"Поделиться",@"Share") forState:UIControlStateNormal];
        [share setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        share.backgroundColor=[UIColor colorWithWhite:0.2 alpha:1]; share.layer.cornerRadius=12;
        [share addTarget:self action:@selector(share) forControlEvents:UIControlEventTouchUpInside]; [self.scroll addSubview:share]; y+=52;
        for(NSString*n in ListCfgs()){
            UIButton*b=[UIButton buttonWithType:UIButtonTypeSystem];
            b.frame=CGRectMake(12,y,self.scroll.bounds.size.width-24,40);
            [b setTitle:n forState:UIControlStateNormal]; [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
            b.backgroundColor=[n isEqualToString:gCfgName]?[UIColor colorWithRed:gAR green:gAG blue:gAB alpha:0.35]:[UIColor colorWithWhite:0.12 alpha:1];
            b.layer.cornerRadius=10; b.accessibilityLabel=n;
            [b addTarget:self action:@selector(loadOne:) forControlEvents:UIControlEventTouchUpInside]; [self.scroll addSubview:b]; y+=48;
        }
    }
    self.scroll.contentSize=CGSizeMake(self.scroll.bounds.size.width,y+16);
    [self relabel]; 
}
- (void)onSw:(UISwitch*)s{
    int t=(int)s.superview.tag; BOOL v=s.on;
    switch(t){case 10:gAim=v;break;case 11:gFovDraw=v;break;case 12:gSilent=v;break;
        case 20:gEsp=v;break;case 21:gBox=v;break;case 22:gName=v;break;case 23:gHP=v;break;
        case 24:gDist=v;break;case 25:gSnap=v;break;case 26:gTeam=v;break;
        case 30:gHideRec=v;ApplyCaptureHide(gWin,self,gHideRec);break;}
    SaveCfgNamed(gCfgName);
}
- (void)onFov:(UISlider*)sl{gFov=sl.value; UILabel*l=[sl.superview viewWithTag:3];
    l.text=[NSString stringWithFormat:@"%.0f | 1-30",gFov]; SaveCfgNamed(gCfgName);}
- (void)tab:(UIButton*)b{gTab=(int)b.tag-100;[self rebuild];}
- (void)togLang{gLang=gLang?0:1;[self rebuild];SaveCfgNamed(gCfgName);}
- (void)col:(UIButton*)b{
    NSArray*cols=@[@[@0.25f,@0.55f,@1.f],@[@0.6f,@0.2f,@1.f],@[@0.1f,@0.85f,@0.5f],@[@1.f,@0.35f,@0.2f],@[@1.f,@0.2f,@0.45f]];
    int i=(int)b.tag-300; if(i<0||i>4)return;
    gAR=[cols[i][0]floatValue];gAG=[cols[i][1]floatValue];gAB=[cols[i][2]floatValue];
    self.panel.layer.borderColor=[UIColor colorWithRed:gAR green:gAG blue:gAB alpha:0.45].CGColor;
    self.fab.layer.borderColor=[UIColor colorWithRed:gAR green:gAG blue:gAB alpha:1].CGColor;
    [self rebuild];SaveCfgNamed(gCfgName);
}
- (void)save{SaveCfgNamed(gCfgName);[self rebuild];}
- (void)loadOne:(UIButton*)b{LoadCfgNamed(b.accessibilityLabel);[self rebuild];}
- (void)share{
    NSData*data=[NSJSONSerialization dataWithJSONObject:CfgDict() options:0 error:nil];
    NSString*s=[[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding];
    UIActivityViewController*ac=[[UIActivityViewController alloc]initWithActivityItems:@[s?:@""] applicationActivities:nil];
    [self.window.rootViewController presentViewController:ac animated:YES completion:nil];
}
- (void)fabTap{gMenu=!gMenu;self.panel.hidden=!gMenu;if(gMenu)[self rebuild];}
- (void)fabPan:(UIPanGestureRecognizer*)g{
    CGPoint t=[g translationInView:self]; CGPoint c=self.fab.center; c.x+=t.x;c.y+=t.y;
    CGFloat h=26; c.x=fmaxf(h,fminf(self.bounds.size.width-h,c.x));
    c.y=fmaxf(h+40,fminf(self.bounds.size.height-h-20,c.y));
    self.fab.center=c; [g setTranslation:CGPointZero inView:self];
}
- (void)panPanel:(UIPanGestureRecognizer*)g{
    CGPoint t=[g translationInView:self]; CGRect f=self.panel.frame;
    f.origin.x+=t.x;f.origin.y+=t.y; self.panel.frame=f; [g setTranslation:CGPointZero inView:self];
}
- (void)drawRect:(CGRect)rect{
    if(!gReady)return; GameTick();
    CGContextRef ctx=UIGraphicsGetCurrentContext(); if(!ctx)return;
    CGFloat W=rect.size.width,H=rect.size.height;
    if(gAim&&gFovDraw){
        CGFloat r=20.f+gFov*4.f;
        CGContextSetStrokeColorWithColor(ctx,[UIColor colorWithRed:gAR green:gAG blue:gAB alpha:0.4].CGColor);
        CGContextSetLineWidth(ctx,1.2);
        CGContextStrokeEllipseInRect(ctx,CGRectMake(W*0.5f-r,H*0.5f-r,r*2,r*2));
    }
    if(!gEsp)return;
    std::lock_guard<std::mutex>lk(gMtx);
    for(size_t i=0;i<gEnts.size();i++){
        const Ent&e=gEnts[i]; if(e.local||e.dead)continue;
        if(gTeam&&e.team==gLocalTeam)continue;
        V2 feet,head; if(!W2S(e.pos,feet,W,H)||!W2S(e.head,head,W,H))continue;
        float h=fabsf(feet.y-head.y),w=h*0.45f,x=head.x-w*0.5f,y=head.y;
        if(gBox){CGContextSetStrokeColorWithColor(ctx,[UIColor colorWithRed:0.3 green:0.7 blue:1 alpha:0.95].CGColor);
            CGContextSetLineWidth(ctx,1.4);CGContextStrokeRect(ctx,CGRectMake(x,y,w,h));}
        if(gHP){float hp=fmaxf(0,fminf(1,e.hp/(e.maxHp>0?e.maxHp:100.f)));
            CGContextSetFillColorWithColor(ctx,[UIColor colorWithRed:1-hp green:hp blue:0.15 alpha:0.9].CGColor);
            CGContextFillRect(ctx,CGRectMake(x-5,y+h*(1-hp),3,h*hp));}
        if(gName||gDist){NSMutableString*s=[NSMutableString string];
            if(gName)[s appendFormat:@"%s",e.name.c_str()]; if(gDist)[s appendFormat:@" [%.0fm]",e.dist];
            [s drawAtPoint:CGPointMake(x,y-13) withAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:10 weight:UIFontWeightMedium],NSForegroundColorAttributeName:[UIColor colorWithRed:0.8 green:0.92 blue:1 alpha:0.95]}];}
        if(gSnap){CGContextSetStrokeColorWithColor(ctx,[UIColor colorWithRed:0.25 green:0.55 blue:1 alpha:0.35].CGColor);
            CGContextSetLineWidth(ctx,0.8);CGContextMoveToPoint(ctx,W*0.5f,H);CGContextAddLineToPoint(ctx,feet.x,feet.y);CGContextStrokePath(ctx);}
    }
}
- (UIView*)hitTest:(CGPoint)p withEvent:(UIEvent*)e{
    if(gMenu&&CGRectContainsPoint(self.panel.frame,p))return [super hitTest:p withEvent:e];
    if(CGRectContainsPoint(self.fab.frame,p))return [super hitTest:p withEvent:e];
    if(gMenu){gMenu=NO;self.panel.hidden=YES;} return nil;
}
- (void)layoutForScreen {
    CGRect b=self.window?self.window.bounds:UIScreen.mainScreen.bounds;
    // handle landscape: use real window bounds
    if(!CGRectEqualToRect(self.frame,b)) self.frame=b;
    CGFloat W=b.size.width, H=b.size.height;
    CGFloat S=52;
    // keep fab on right side relative to current size
    if(self.fab.center.x<10||self.fab.center.x>W-10||self.fab.center.y<10){
        self.fab.frame=CGRectMake(W-S-14, H*0.45, S, S);
    }
    CGFloat pw=fminf(W-20, 560), ph=fminf(H-40, 320);
    if(W>H){ // landscape — wider panel
        pw=fminf(W*0.85, 640);
        ph=fminf(H*0.85, 340);
    }
    if(self.panel.hidden || self.panel.bounds.size.width<50){
        self.panel.frame=CGRectMake((W-pw)/2,(H-ph)/2,pw,ph);
    }
    CGFloat sw=130;
    self.side.frame=CGRectMake(0,0,sw,self.panel.bounds.size.height);
    self.scroll.frame=CGRectMake(sw,0,self.panel.bounds.size.width-sw,self.panel.bounds.size.height);
    if(gSecureField) gSecureField.frame=b;
    if(gSecureContainer) self.frame=gSecureContainer.bounds;
}
- (void)boot{
    gReady=YES; LoadCfgNamed(@"default");
    self.link=[CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    self.link.preferredFramesPerSecond=60;
    [self.link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(orient) name:UIDeviceOrientationDidChangeNotification object:nil];
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
    [self layoutForScreen];
    ApplyCaptureHide(gWin,self,gHideRec);
}
- (void)orient{
    dispatch_async(dispatch_get_main_queue(),^{
        if(gWin){
            gWin.frame=UIScreen.mainScreen.bounds;
            [self layoutForScreen];
            ApplyCaptureHide(gWin,self,gHideRec);
            if(gMenu)[self rebuild];
        }
    });
}
- (void)tick:(CADisplayLink*)l{
    // refresh bounds if game rotated without notification
    CGRect b=UIScreen.mainScreen.bounds;
    if(gWin && !CGRectEqualToRect(gWin.frame,b)){
        gWin.frame=b;
        [self layoutForScreen];
    }
    [self setNeedsDisplay];
}
- (void)dealloc{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}
@end

static void Start(){
    if(gWin)return;
    dispatch_async(dispatch_get_main_queue(),^{
        CGRect b=UIScreen.mainScreen.bounds;
        gWin=[[ACW alloc]initWithFrame:b];
        gWin.windowLevel=UIWindowLevelAlert+100;
        gWin.backgroundColor=UIColor.clearColor;
        gWin.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        UIViewController*r=[UIViewController new];
        r.view.backgroundColor=UIColor.clearColor;
        r.view.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        // allow all orientations so HUD matches landscape game
        if([r respondsToSelector:@selector(setModalPresentationStyle:)]){}
        gWin.rootViewController=r;
        gHud=[[ACH alloc]initWithFrame:b];
        gHud.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        [r.view addSubview:gHud];
        [gWin makeKeyAndVisible];
        [gHud boot];
        NSLog(@"[Astral] ready landscape-aware");
    });
}
__attribute__((constructor)) static void onLoad(){
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(2*NSEC_PER_SEC)),dispatch_get_main_queue(),^{Start();});
}
