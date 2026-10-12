// Astral dylib — landscape follows game window, touches pass through, capture hide
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
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

struct V3{float x,y,z; V3(float a=0,float b=0,float c=0):x(a),y(b),z(c){}};
struct V2{float x,y;};
struct M4{float m[16]{};};
struct Ent{V3 pos,head;float hp,maxHp,dist;int team;bool local,dead;std::string name;};
static std::vector<Ent> gEnts; static std::mutex gMtx;
static bool gHasVM=false; static M4 gVM;

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
static void GameTick(){}

@class ACH;
static ACH *gHud=nil;

@interface ACW:UIWindow @end
@interface ACVC:UIViewController @end
@implementation ACVC
- (BOOL)shouldAutorotate { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskLandscapeLeft|UIInterfaceOrientationMaskLandscapeRight;
}
- (BOOL)prefersStatusBarHidden { return YES; }
@end

@interface ACH:UIView
@property(nonatomic,strong)CADisplayLink*link;
@property(nonatomic,strong)UIView*fab,*panel,*side;
@property(nonatomic,strong)UIScrollView*scroll;
@property(nonatomic,strong)UITextField*secureTF;
- (void)rebuild;
- (void)relayout;
- (void)applyHide;
@end

static ACW *gWin=nil;

static UIWindow *GameWindow(void){
    UIWindow *best=nil; CGFloat area=0;
    for(UIWindow *w in UIApplication.sharedApplication.windows){
        if(w==gWin||w.hidden) continue;
        CGFloat a=w.bounds.size.width*w.bounds.size.height;
        if(a>area){ area=a; best=w; }
    }
    return best;
}

@implementation ACW
- (BOOL)_isSecure { return gHideRec; }
- (BOOL)isSecure { return gHideRec; }
- (BOOL)_shouldCreateContextAsSecure { return gHideRec; }
// Only the icon and open menu eat touches. Everything else goes to the game.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit=[super hitTest:point withEvent:event];
    UIView *v=hit;
    while(v){
        if(gHud && (v==gHud.panel || v==gHud.fab)) return hit;
        v=v.superview;
    }
    return nil;
}
@end

@implementation ACH

- (instancetype)initWithFrame:(CGRect)f{
    self=[super initWithFrame:f]; if(!self)return nil;
    self.backgroundColor=UIColor.clearColor;
    self.opaque=NO;
    self.userInteractionEnabled=YES;
    self.multipleTouchEnabled=YES;

    CGFloat S=52;
    self.fab=[[UIView alloc]initWithFrame:CGRectMake(20,20,S,S)];
    self.fab.backgroundColor=[UIColor colorWithRed:0.08 green:0.15 blue:0.3 alpha:0.95];
    self.fab.layer.cornerRadius=S/2;
    self.fab.layer.borderWidth=2;
    self.fab.layer.borderColor=[UIColor colorWithRed:gAR green:gAG blue:gAB alpha:1].CGColor;
    self.fab.userInteractionEnabled=YES;
    UILabel*fl=[[UILabel alloc]initWithFrame:self.fab.bounds];
    fl.text=@"A"; fl.textAlignment=NSTextAlignmentCenter; fl.userInteractionEnabled=NO;
    fl.font=[UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    fl.textColor=[UIColor colorWithRed:0.55 green:0.85 blue:1 alpha:1];
    [self.fab addSubview:fl];
    [self.fab addGestureRecognizer:[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(fabTap)]];
    [self.fab addGestureRecognizer:[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(fabPan:)]];
    [self addSubview:self.fab];

    self.panel=[[UIView alloc]initWithFrame:CGRectMake(40,40,560,280)];
    self.panel.backgroundColor=[UIColor colorWithRed:0.04 green:0.07 blue:0.12 alpha:0.97];
    self.panel.layer.cornerRadius=16;
    self.panel.layer.borderWidth=1;
    self.panel.layer.borderColor=[UIColor colorWithRed:gAR green:gAG blue:gAB alpha:0.45].CGColor;
    self.panel.userInteractionEnabled=YES;
    self.panel.clipsToBounds=YES;
    self.panel.hidden=YES;
    [self addSubview:self.panel];

    self.side=[[UIView alloc]initWithFrame:CGRectMake(0,0,120,280)];
    self.side.backgroundColor=[UIColor colorWithRed:0.03 green:0.05 blue:0.1 alpha:1];
    self.side.userInteractionEnabled=YES;
    [self.panel addSubview:self.side];

    UILabel*lg=[[UILabel alloc]initWithFrame:CGRectMake(4,8,112,28)];
    lg.text=@"ASTRAL"; lg.textAlignment=NSTextAlignmentCenter;
    lg.font=[UIFont systemFontOfSize:14 weight:UIFontWeightBlack];
    lg.textColor=[UIColor colorWithRed:0.4 green:0.75 blue:1 alpha:1];
    lg.userInteractionEnabled=NO;
    [self.side addSubview:lg];

    for(int i=0;i<4;i++){
        UIButton*b=[UIButton buttonWithType:UIButtonTypeSystem];
        b.frame=CGRectMake(6,42+i*40,108,34);
        b.tag=100+i; b.layer.cornerRadius=8;
        [b addTarget:self action:@selector(tab:) forControlEvents:UIControlEventTouchUpInside];
        [self.side addSubview:b];
    }
    UIButton*lang=[UIButton buttonWithType:UIButtonTypeSystem];
    lang.frame=CGRectMake(6,240,108,28); lang.tag=200;
    [lang addTarget:self action:@selector(togLang) forControlEvents:UIControlEventTouchUpInside];
    [self.side addSubview:lang];

    self.scroll=[[UIScrollView alloc]initWithFrame:CGRectMake(120,0,440,280)];
    self.scroll.userInteractionEnabled=YES;
    self.scroll.delaysContentTouches=NO;
    self.scroll.canCancelContentTouches=YES;
    self.scroll.alwaysBounceVertical=YES;
    [self.panel addSubview:self.scroll];
    [self.side addGestureRecognizer:[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(panPanel:)]];
    [self rebuild];
    return self;
}

- (void)relayout{
    UIWindow *game=GameWindow();
    if(gWin && game){
        gWin.transform=game.transform;
        gWin.bounds=game.bounds;
        gWin.center=game.center;
    }
    CGRect b=gWin?gWin.bounds:UIScreen.mainScreen.bounds;
    self.frame=b;
    CGFloat W=b.size.width, H=b.size.height;
    CGFloat S=52;
    CGPoint c=self.fab.center;
    if(c.x<S || c.y<S || c.x>W-4 || c.y>H-4)
        self.fab.frame=CGRectMake(W-S-18, H*0.45f, S, S);
    else {
        c.x=fminf(W-S*0.5f-6, fmaxf(S*0.5f+6, c.x));
        c.y=fminf(H-S*0.5f-6, fmaxf(S*0.5f+6, c.y));
        self.fab.center=c;
    }
    CGFloat pw=fminf(W*0.9f, 640);
    CGFloat ph=fminf(H*0.86f, 320);
    if(W<H){ pw=fminf(W-16, 340); ph=fminf(H*0.72f, 420); }
    self.panel.bounds=CGRectMake(0,0,pw,ph);
    if(self.panel.center.x<20 || self.panel.center.y<20)
        self.panel.center=CGPointMake(W*0.5f, H*0.5f);
    CGFloat sw=118;
    self.side.frame=CGRectMake(0,0,sw,ph);
    self.scroll.frame=CGRectMake(sw,0,pw-sw,ph);
    UIButton*lang=(UIButton*)[self.side viewWithTag:200];
    lang.frame=CGRectMake(6, ph-34, sw-12, 26);
    if(self.secureTF){
        self.secureTF.frame=self.superview?self.superview.bounds:b;
    }
}

- (UIView *)secureCanvas{
    if(!self.secureTF) return nil;
    [self.secureTF layoutIfNeeded];
    UIView *canvas=nil;
    for(UIView *sub in self.secureTF.subviews){
        NSString *cls=NSStringFromClass(sub.class);
        if([cls containsString:@"Canvas"]||[cls containsString:@"TextLayout"]||[cls containsString:@"Field"]){
            canvas=sub; break;
        }
    }
    if(!canvas && self.secureTF.subviews.count) canvas=self.secureTF.subviews.lastObject;
    if(!canvas && self.secureTF.subviews.count) canvas=self.secureTF.subviews.firstObject;
    return canvas;
}

- (void)applyHide{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    SEL sec=NSSelectorFromString(@"_setSecure:");
    if(gWin && [gWin respondsToSelector:sec]) ((void(*)(id,SEL,BOOL))objc_msgSend)(gWin,sec,gHideRec);
#pragma clang diagnostic pop
    UIView *root=gWin.rootViewController.view;
    if(!gHideRec){
        [self.secureTF removeFromSuperview];
        if(self.superview!=root){
            [self removeFromSuperview];
            self.frame=root.bounds;
            [root addSubview:self];
        }
        return;
    }
    if(!self.secureTF){
        self.secureTF=[[UITextField alloc]initWithFrame:root.bounds];
        self.secureTF.secureTextEntry=YES;
        self.secureTF.backgroundColor=UIColor.clearColor;
        self.secureTF.userInteractionEnabled=YES;
        self.secureTF.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    }
    self.secureTF.frame=root.bounds;
    if(self.secureTF.superview!=root) [root addSubview:self.secureTF];
    UIView *canvas=[self secureCanvas];
    if(canvas){
        canvas.userInteractionEnabled=YES;
        canvas.backgroundColor=UIColor.clearColor;
        if(self.superview!=canvas){
            [self removeFromSuperview];
            self.frame=canvas.bounds;
            self.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
            [canvas addSubview:self];
        }
    }
}

- (void)relabel{
    NSArray*ru=@[@"Прицел",@"Визуалы",@"Разное",@"Конфиг"];
    NSArray*en=@[@"Aim",@"Visuals",@"Misc",@"Config"];
    for(int i=0;i<4;i++){
        UIButton*b=(UIButton*)[self.side viewWithTag:100+i];
        [b setTitle:(gLang==0?ru[i]:en[i]) forState:UIControlStateNormal];
        BOOL on=gTab==i;
        [b setTitleColor:on?UIColor.whiteColor:[UIColor colorWithWhite:0.55 alpha:1] forState:UIControlStateNormal];
        b.backgroundColor=on?[UIColor colorWithRed:gAR green:gAG blue:gAB alpha:0.35]:UIColor.clearColor;
        b.titleLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    }
    UIButton*l=(UIButton*)[self.side viewWithTag:200];
    [l setTitle:(gLang==0?@"RU | EN":@"EN | RU") forState:UIControlStateNormal];
    [l setTitleColor:[UIColor colorWithWhite:0.55 alpha:1] forState:UIControlStateNormal];
}

- (void)card:(NSString*)title sub:(NSString*)sub y:(CGFloat)y tag:(int)tag on:(BOOL)on sl:(BOOL)sl{
    CGFloat w=self.scroll.bounds.size.width>30?self.scroll.bounds.size.width-16:300;
    UIView*c=[[UIView alloc]initWithFrame:CGRectMake(8,y,w,sl?82:56)];
    c.backgroundColor=[UIColor colorWithRed:0.06 green:0.1 blue:0.18 alpha:1];
    c.layer.cornerRadius=12; c.layer.borderWidth=1;
    c.layer.borderColor=[UIColor colorWithRed:gAR green:gAG blue:gAB alpha:0.25].CGColor;
    c.tag=tag; c.userInteractionEnabled=YES;
    UILabel*t=[[UILabel alloc]initWithFrame:CGRectMake(12,6,w-80,20)];
    t.text=title; t.font=[UIFont systemFontOfSize:14 weight:UIFontWeightSemibold]; t.textColor=UIColor.whiteColor;
    t.userInteractionEnabled=NO; [c addSubview:t];
    UILabel*s=[[UILabel alloc]initWithFrame:CGRectMake(12,26,w-80,14)];
    s.text=sub; s.font=[UIFont systemFontOfSize:10]; s.textColor=[UIColor colorWithWhite:0.5 alpha:1];
    s.userInteractionEnabled=NO; [c addSubview:s];
    UISwitch*sw=[[UISwitch alloc]initWithFrame:CGRectZero];
    sw.on=on; sw.tag=1; sw.onTintColor=[UIColor colorWithRed:gAR green:gAG blue:gAB alpha:1];
    sw.center=CGPointMake(w-40, 26);
    [sw addTarget:self action:@selector(onSw:) forControlEvents:UIControlEventValueChanged];
    [c addSubview:sw];
    if(sl){
        UISlider*slid=[[UISlider alloc]initWithFrame:CGRectMake(12,50,w-86,22)];
        slid.minimumValue=1; slid.maximumValue=30; slid.value=gFov; slid.tag=2;
        slid.minimumTrackTintColor=[UIColor colorWithRed:gAR green:gAG blue:gAB alpha:1];
        [slid addTarget:self action:@selector(onFov:) forControlEvents:UIControlEventValueChanged];
        [c addSubview:slid];
        UILabel*lv=[[UILabel alloc]initWithFrame:CGRectMake(w-72,50,62,22)]; lv.tag=3;
        lv.textAlignment=NSTextAlignmentRight; lv.font=[UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
        lv.textColor=[UIColor colorWithWhite:0.7 alpha:1];
        lv.text=[NSString stringWithFormat:@"%.0f|1-30",gFov]; [c addSubview:lv];
    }
    [self.scroll addSubview:c];
}

- (void)rebuild{
    for(UIView*v in [self.scroll.subviews copy])[v removeFromSuperview];
    CGFloat y=8;
    if(gTab==0){
        [self card:T(@"Аимбот",@"Aim bot") sub:T(@"Автоприцел",@"Auto aim") y:y tag:10 on:gAim sl:NO]; y+=66;
        [self card:T(@"Круг FOV",@"FOV Circle") sub:T(@"1–30",@"1-30") y:y tag:11 on:gFovDraw sl:YES]; y+=92;
        [self card:T(@"Сайлент",@"Silent") sub:T(@"Скрытый аим",@"Silent aim") y:y tag:12 on:gSilent sl:NO]; y+=66;
    }else if(gTab==1){
        [self card:@"ESP" sub:@"" y:y tag:20 on:gEsp sl:NO]; y+=66;
        [self card:T(@"Бокс",@"Box") sub:@"" y:y tag:21 on:gBox sl:NO]; y+=66;
        [self card:T(@"Имя",@"Name") sub:@"" y:y tag:22 on:gName sl:NO]; y+=66;
        [self card:T(@"ХП",@"HP") sub:@"" y:y tag:23 on:gHP sl:NO]; y+=66;
        [self card:T(@"Дистанция",@"Distance") sub:@"" y:y tag:24 on:gDist sl:NO]; y+=66;
        [self card:T(@"Линии",@"Snaplines") sub:@"" y:y tag:25 on:gSnap sl:NO]; y+=66;
        [self card:T(@"Тимчек",@"Team") sub:@"" y:y tag:26 on:gTeam sl:NO]; y+=66;
    }else if(gTab==2){
        [self card:T(@"Скрыть запись",@"Hide Recording") sub:T(@"Скрин и запись экрана",@"Screenshot and recording") y:y tag:30 on:gHideRec sl:NO]; y+=66;
        UILabel*cl=[[UILabel alloc]initWithFrame:CGRectMake(12,y,200,16)];
        cl.text=T(@"Цвет",@"Color"); cl.textColor=[UIColor colorWithWhite:0.6 alpha:1];
        cl.font=[UIFont systemFontOfSize:12]; [self.scroll addSubview:cl]; y+=22;
        NSArray*cols=@[@[@0.25f,@0.55f,@1.f],@[@0.6f,@0.2f,@1.f],@[@0.1f,@0.85f,@0.5f],@[@1.f,@0.35f,@0.2f],@[@1.f,@0.2f,@0.45f]];
        for(int i=0;i<5;i++){
            UIButton*b=[UIButton buttonWithType:UIButtonTypeCustom];
            b.frame=CGRectMake(12+i*46,y,34,34); b.layer.cornerRadius=17; b.tag=300+i;
            b.backgroundColor=[UIColor colorWithRed:[cols[i][0]floatValue] green:[cols[i][1]floatValue] blue:[cols[i][2]floatValue] alpha:1];
            [b addTarget:self action:@selector(col:) forControlEvents:UIControlEventTouchUpInside];
            [self.scroll addSubview:b];
        }
        y+=46;
    }else{
        UILabel*cur=[[UILabel alloc]initWithFrame:CGRectMake(12,y,280,16)];
        cur.text=[NSString stringWithFormat:@"%@: %@",T(@"Текущий",@"Current"),gCfgName];
        cur.textColor=[UIColor colorWithWhite:0.65 alpha:1]; [self.scroll addSubview:cur]; y+=24;
        CGFloat bw=MAX(80,(self.scroll.bounds.size.width-28)/2);
        UIButton*save=[UIButton buttonWithType:UIButtonTypeSystem];
        save.frame=CGRectMake(8,y,bw,34);
        [save setTitle:T(@"Сохранить",@"Save") forState:UIControlStateNormal];
        [save setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        save.backgroundColor=[UIColor colorWithRed:gAR green:gAG blue:gAB alpha:0.5]; save.layer.cornerRadius=10;
        [save addTarget:self action:@selector(save) forControlEvents:UIControlEventTouchUpInside];
        [self.scroll addSubview:save];
        UIButton*share=[UIButton buttonWithType:UIButtonTypeSystem];
        share.frame=CGRectMake(12+bw,y,bw,34);
        [share setTitle:T(@"Поделиться",@"Share") forState:UIControlStateNormal];
        [share setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        share.backgroundColor=[UIColor colorWithWhite:0.2 alpha:1]; share.layer.cornerRadius=10;
        [share addTarget:self action:@selector(share) forControlEvents:UIControlEventTouchUpInside];
        [self.scroll addSubview:share]; y+=44;
        for(NSString*n in ListCfgs()){
            UIButton*b=[UIButton buttonWithType:UIButtonTypeSystem];
            b.frame=CGRectMake(8,y,MAX(120,self.scroll.bounds.size.width-16),34);
            [b setTitle:n forState:UIControlStateNormal]; [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
            b.backgroundColor=[n isEqualToString:gCfgName]?[UIColor colorWithRed:gAR green:gAG blue:gAB alpha:0.35]:[UIColor colorWithWhite:0.12 alpha:1];
            b.layer.cornerRadius=10; b.accessibilityLabel=n;
            [b addTarget:self action:@selector(loadOne:) forControlEvents:UIControlEventTouchUpInside];
            [self.scroll addSubview:b]; y+=42;
        }
    }
    self.scroll.contentSize=CGSizeMake(self.scroll.bounds.size.width, y+12);
    [self relabel];
}

- (void)onSw:(UISwitch*)s{
    int t=(int)s.superview.tag; BOOL v=s.on;
    switch(t){
        case 10:gAim=v;break; case 11:gFovDraw=v;break; case 12:gSilent=v;break;
        case 20:gEsp=v;break; case 21:gBox=v;break; case 22:gName=v;break; case 23:gHP=v;break;
        case 24:gDist=v;break; case 25:gSnap=v;break; case 26:gTeam=v;break;
        case 30:gHideRec=v; [self applyHide]; break;
    }
    SaveCfgNamed(gCfgName);
}
- (void)onFov:(UISlider*)sl{
    gFov=sl.value;
    UILabel*l=[sl.superview viewWithTag:3];
    l.text=[NSString stringWithFormat:@"%.0f|1-30",gFov];
    SaveCfgNamed(gCfgName);
}
- (void)tab:(UIButton*)b{ gTab=(int)b.tag-100; [self rebuild]; }
- (void)togLang{ gLang=gLang?0:1; [self rebuild]; SaveCfgNamed(gCfgName); }
- (void)col:(UIButton*)b{
    NSArray*cols=@[@[@0.25f,@0.55f,@1.f],@[@0.6f,@0.2f,@1.f],@[@0.1f,@0.85f,@0.5f],@[@1.f,@0.35f,@0.2f],@[@1.f,@0.2f,@0.45f]];
    int i=(int)b.tag-300; if(i<0||i>4)return;
    gAR=[cols[i][0]floatValue]; gAG=[cols[i][1]floatValue]; gAB=[cols[i][2]floatValue];
    self.panel.layer.borderColor=[UIColor colorWithRed:gAR green:gAG blue:gAB alpha:0.45].CGColor;
    self.fab.layer.borderColor=[UIColor colorWithRed:gAR green:gAG blue:gAB alpha:1].CGColor;
    [self rebuild]; SaveCfgNamed(gCfgName);
}
- (void)save{ SaveCfgNamed(gCfgName); [self rebuild]; }
- (void)loadOne:(UIButton*)b{ LoadCfgNamed(b.accessibilityLabel); [self rebuild]; }
- (void)share{
    NSData*data=[NSJSONSerialization dataWithJSONObject:CfgDict() options:0 error:nil];
    NSString*s=[[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding];
    UIActivityViewController*ac=[[UIActivityViewController alloc]initWithActivityItems:@[s?:@""] applicationActivities:nil];
    [gWin.rootViewController presentViewController:ac animated:YES completion:nil];
}
- (void)fabTap{ gMenu=!gMenu; self.panel.hidden=!gMenu; if(gMenu){[self relayout];[self rebuild];} }
- (void)fabPan:(UIPanGestureRecognizer*)g{
    CGPoint t=[g translationInView:self];
    CGPoint c=self.fab.center; c.x+=t.x; c.y+=t.y;
    CGFloat h=26, W=self.bounds.size.width, H=self.bounds.size.height;
    c.x=fmaxf(h,fminf(W-h,c.x)); c.y=fmaxf(h,fminf(H-h,c.y));
    self.fab.center=c; [g setTranslation:CGPointZero inView:self];
}
- (void)panPanel:(UIPanGestureRecognizer*)g{
    CGPoint t=[g translationInView:self];
    CGPoint c=self.panel.center; c.x+=t.x; c.y+=t.y;
    self.panel.center=c; [g setTranslation:CGPointZero inView:self];
}

- (void)drawRect:(CGRect)rect{
    if(!gReady)return; GameTick();
    CGContextRef ctx=UIGraphicsGetCurrentContext(); if(!ctx)return;
    CGFloat W=rect.size.width, H=rect.size.height;
    if(gAim&&gFovDraw){
        CGFloat r=18.f+gFov*3.2f;
        CGContextSetStrokeColorWithColor(ctx,[UIColor colorWithRed:gAR green:gAG blue:gAB alpha:0.45].CGColor);
        CGContextSetLineWidth(ctx,1.2);
        CGContextStrokeEllipseInRect(ctx,CGRectMake(W*0.5f-r,H*0.5f-r,r*2,r*2));
    }
}

- (UIView*)hitTest:(CGPoint)p withEvent:(UIEvent*)e{
    if(!gReady) return nil;
    if(gMenu && !self.panel.hidden){
        CGPoint pp=[self convertPoint:p toView:self.panel];
        if([self.panel pointInside:pp withEvent:e]){
            UIView*v=[self.panel hitTest:pp withEvent:e];
            return v?:self.panel;
        }
    }
    CGPoint fp=[self convertPoint:p toView:self.fab];
    if([self.fab pointInside:fp withEvent:e]) return self.fab;
    return nil;
}

- (void)boot{
    gReady=YES;
    LoadCfgNamed(@"default");
    [self relayout];
    [self applyHide];
    self.link=[CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    self.link.preferredFramesPerSecond=30;
    [self.link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onOrient) name:UIDeviceOrientationDidChangeNotification object:nil];
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
}
- (void)onOrient{
    dispatch_async(dispatch_get_main_queue(),^{ [self relayout]; if(gMenu)[self rebuild]; });
}
- (void)tick:(CADisplayLink*)l{
    UIWindow *game=GameWindow();
    if(gWin && game){
        BOOL moved=!CGAffineTransformEqualToTransform(gWin.transform, game.transform)
            || fabs(gWin.bounds.size.width-game.bounds.size.width)>1
            || fabs(gWin.bounds.size.height-game.bounds.size.height)>1
            || fabs(gWin.center.x-game.center.x)>1
            || fabs(gWin.center.y-game.center.y)>1;
        if(moved) [self relayout];
    }
    [self setNeedsDisplay];
}
@end

static void Start(void){
    if(gWin)return;
    dispatch_async(dispatch_get_main_queue(),^{
        UIWindow *game=GameWindow();
        CGRect b=game?game.bounds:UIScreen.mainScreen.bounds;
        gWin=[[ACW alloc] initWithFrame:b];
        if(game){
            gWin.transform=game.transform;
            gWin.bounds=game.bounds;
            gWin.center=game.center;
        }
        gWin.windowLevel=UIWindowLevelAlert+50;
        gWin.backgroundColor=UIColor.clearColor;
        gWin.userInteractionEnabled=YES;
        ACVC *r=[ACVC new];
        r.view.backgroundColor=UIColor.clearColor;
        r.view.userInteractionEnabled=YES;
        gWin.rootViewController=r;
        gHud=[[ACH alloc] initWithFrame:gWin.bounds];
        [r.view addSubview:gHud];
        UIWindow *prev=UIApplication.sharedApplication.keyWindow;
        gWin.hidden=NO;
        [gWin makeKeyAndVisible];
        if(prev && prev!=gWin) [prev makeKeyWindow];
        [gHud boot];
    });
}

__attribute__((constructor))
static void onLoad(void){
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(2.0*NSEC_PER_SEC)), dispatch_get_main_queue(),^{ Start(); });
}
