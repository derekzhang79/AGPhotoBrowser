//
//  AGPhotoBrowserView.m
//  AGPhotoBrowser
//
//  Created by Hellrider on 7/28/13.
//  Copyright (c) 2013 Andrea Giavatto. All rights reserved.
//

#import "AGPhotoBrowserView.h"

#import <QuartzCore/QuartzCore.h>
#import "AGPhotoBrowserOverlayView.h"
#import "AGPhotoBrowserZoomableView.h"



@interface AGPhotoBrowserView () <
AGPhotoBrowserOverlayViewDelegate,
AGPhotoBrowserZoomableViewDelegate,
UITableViewDataSource,
UITableViewDelegate,
UIGestureRecognizerDelegate
> {
	CGPoint _startingPanPoint;
	BOOL _wantedFullscreenLayout;
    BOOL _navigationBarWasHidden;
	CGRect _originalParentViewFrame;
	NSInteger _currentlySelectedIndex;
}

@property (nonatomic, strong, readwrite) UIButton *doneButton;
@property (nonatomic, strong) UITableView *photoTableView;
@property (nonatomic, strong) AGPhotoBrowserOverlayView *overlayView;
@property (nonatomic, strong) UIWindow *previousWindow;
@property (nonatomic, strong) UIWindow *currentWindow;

@property (nonatomic, assign, getter = isDisplayingDetailedView) BOOL displayingDetailedView;

@end


static NSString *CellIdentifier = @"AGPhotoBrowserCell";

@implementation AGPhotoBrowserView

const NSInteger AGPhotoBrowserThresholdToCenter = 150;

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:[UIScreen mainScreen].bounds];
    if (self) {
        // Initialization code
		[self setupView];
    }
    return self;
}

- (void)setupView
{
	self.userInteractionEnabled = NO;
	self.backgroundColor = [UIColor colorWithWhite:0. alpha:0.];
    //self.translatesAutoresizingMaskIntoConstraints = NO;
	_currentlySelectedIndex = NSNotFound;
	
	[self addSubview:self.photoTableView];
	//[self addSubview:self.doneButton];
	//[self addSubview:self.overlayView];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(statusBarDidChangeFrame:)
                                                 name:UIDeviceOrientationDidChangeNotification
                                               object:nil];
}

- (void)updateConstraints
{
    [self removeConstraints:self.constraints];
    
    NSDictionary *constrainedViews = NSDictionaryOfVariableBindings(_photoTableView/*, _doneButton, _overlayView*/);
    
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[_photoTableView]|"
                                                                 options:0
                                                                 metrics:@{}
                                                                   views:constrainedViews]];
    
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[_photoTableView]|"
                                                                 options:0
                                                                 metrics:@{}
                                                                   views:constrainedViews]];
    /*
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-(==20)-[_doneButton(==32)]-(>=0)-|"
                                                                 options:0
                                                                 metrics:@{}
                                                                   views:constrainedViews]];
    
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-(>=0)-[_doneButton(==60)]-(==10)-|"
                                                                 options:0
                                                                 metrics:@{}
                                                                   views:constrainedViews]];
    
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-(>=0)-[_overlayView(==OverlayHeight)]|"
                                                                 options:0
                                                                 metrics:@{@"OverlayHeight" : @(AGPhotoBrowserOverlayInitialHeight)}
                                                                   views:constrainedViews]];
    
    [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[_overlayView]|"
                                                                 options:0
                                                                 metrics:@{}
                                                                   views:constrainedViews]];*/
    
    [super updateConstraints];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}


#pragma mark - Setters

- (void)setDisplayingDetailedView:(BOOL)displayingDetailedView
{
	_displayingDetailedView = displayingDetailedView;
	
	CGFloat newAlpha;
	
	if (_displayingDetailedView) {
		[self.overlayView showOverlayAnimated:YES];
		newAlpha = 1.;
	} else {
		[self.overlayView hideOverlayAnimated:YES];
		newAlpha = 0.;
	}
	
	[UIView animateWithDuration:AGPhotoBrowserAnimationDuration
					 animations:^(){
						 self.doneButton.alpha = newAlpha;
					 }];
}


#pragma mark - Getters

- (UIButton *)doneButton
{
	if (!_doneButton) {
		int currentScreenWidth = CGRectGetWidth([[UIScreen mainScreen] bounds]);
		_doneButton = [[UIButton alloc] initWithFrame:CGRectMake(currentScreenWidth - 60 - 10, 20, 60, 32)];
        _doneButton.translatesAutoresizingMaskIntoConstraints = NO;
		[_doneButton setTitle:NSLocalizedString(@"Done", @"Title for Done button") forState:UIControlStateNormal];
		_doneButton.layer.cornerRadius = 3.0f;
		_doneButton.layer.borderColor = [UIColor colorWithWhite:0.9 alpha:0.9].CGColor;
		_doneButton.layer.borderWidth = 1.0f;
		[_doneButton setBackgroundColor:[UIColor colorWithWhite:0.1 alpha:0.5]];
		[_doneButton setTitleColor:[UIColor colorWithWhite:0.9 alpha:0.9] forState:UIControlStateNormal];
		[_doneButton setTitleColor:[UIColor colorWithWhite:0.9 alpha:0.9] forState:UIControlStateHighlighted];
		[_doneButton.titleLabel setFont:[UIFont boldSystemFontOfSize:14.0f]];
		_doneButton.alpha = 0.;
		
		[_doneButton addTarget:self action:@selector(p_doneButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
	}
	
	return _doneButton;
}

- (UITableView *)photoTableView
{
	if (!_photoTableView) {
		CGRect screenBounds = [[UIScreen mainScreen] bounds];
		_photoTableView = [[UITableView alloc] initWithFrame:CGRectZero];
        _photoTableView.translatesAutoresizingMaskIntoConstraints = NO;
		_photoTableView.dataSource = self;
		_photoTableView.delegate = self;
		_photoTableView.separatorStyle = UITableViewCellSeparatorStyleNone;
		_photoTableView.backgroundColor = [UIColor clearColor];
		_photoTableView.rowHeight = screenBounds.size.width;
		_photoTableView.pagingEnabled = YES;
		_photoTableView.showsVerticalScrollIndicator = NO;
		_photoTableView.showsHorizontalScrollIndicator = NO;
		_photoTableView.alpha = 0.;
		
		// -- Rotate table horizontally
		CGAffineTransform rotateTable = CGAffineTransformMakeRotation(M_PI_2);
		CGPoint origin = _photoTableView.frame.origin;
		_photoTableView.transform = rotateTable;
		CGRect frame = _photoTableView.frame;
		frame.origin = origin;
		_photoTableView.frame = frame;
	}
	
	return _photoTableView;
}

- (AGPhotoBrowserOverlayView *)overlayView
{
	if (!_overlayView) {
		_overlayView = [[AGPhotoBrowserOverlayView alloc] initWithFrame:CGRectMake(0, CGRectGetHeight(self.frame) - AGPhotoBrowserOverlayInitialHeight, CGRectGetWidth(self.frame), AGPhotoBrowserOverlayInitialHeight)];
        _overlayView.translatesAutoresizingMaskIntoConstraints = NO;
		_overlayView.delegate = self;
	}
	
	return _overlayView;
}


#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	NSInteger number = [_dataSource numberOfPhotosForPhotoBrowser:self];
    
    if (number > 0 && _currentlySelectedIndex == NSNotFound) {
        // initialize with info for the first photo in photoTable
        [self setupPhotoForIndex:0];
    }
    
    return number;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    /*CGFloat rowHeight;
    UIInterfaceOrientation statusBarOrientation = [[UIApplication sharedApplication] statusBarOrientation];
    //UIInterfaceOrientation orientation = 1 << statusBarOrientation;
    if (UIDeviceOrientationIsLandscape(statusBarOrientation)) {
        rowHeight = CGRectGetHeight(self.photoTableView.frame);
    } else {
        rowHeight = CGRectGetWidth(self.photoTableView.frame);
    }
    NSLog(@"Row height %f", rowHeight);
    NSLog(@"Table frame %@", NSStringFromCGRect(tableView.frame));*/
    
    return CGRectGetWidth(self.photoTableView.frame);
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
	cell.backgroundColor = [UIColor clearColor];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    
    [self configureCell:cell forRowAtIndexPath:indexPath];
    
    return cell;
}

- (void)configureCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
    AGPhotoBrowserZoomableView *imageView = (AGPhotoBrowserZoomableView *)[cell.contentView viewWithTag:1];
	if (!imageView) {
		imageView = [[AGPhotoBrowserZoomableView alloc] initWithFrame:self.bounds];
		imageView.userInteractionEnabled = YES;
        imageView.zoomableDelegate = self;
		
		UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(p_imageViewPanned:)];
		panGesture.delegate = self;
		panGesture.maximumNumberOfTouches = 1;
		panGesture.minimumNumberOfTouches = 1;
		[imageView addGestureRecognizer:panGesture];
		imageView.tag = 1;
        
		CGAffineTransform transform = CGAffineTransformMakeRotation(M_PI_2);
		CGPoint origin = imageView.frame.origin;
		imageView.transform = transform;
        CGRect frame = imageView.frame;
        frame.origin = origin;
        imageView.frame = frame;
		
		[cell.contentView addSubview:imageView];
	}
    else {
        // reset to 'zoom out' state
        //imageView.frame = self.bounds;
        [imageView setZoomScale:1.0f];
        
        /*CGAffineTransform transform = CGAffineTransformMakeRotation(M_PI_2);
        if (! CGAffineTransformEqualToTransform(imageView.transform, transform)) {
            imageView.transform = transform;
        }*/
    }
	
    [imageView setImage:[_dataSource photoBrowser:self imageAtIndex:indexPath.row]];
    //NSLog(@"Cell frame %@", NSStringFromCGRect(cell.frame));
}


#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    self.displayingDetailedView = !self.isDisplayingDetailedView;
}

- (void)didTapZoomableView:(AGPhotoBrowserZoomableView *)zoomableView
{
    self.displayingDetailedView = !self.isDisplayingDetailedView;
}


#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
	[self.overlayView resetOverlayView];
	
	CGPoint targetContentOffset = scrollView.contentOffset;
    
	UITableView *tableView = (UITableView*)scrollView;
	NSIndexPath *indexPathOfTopRowAfterScrolling = [tableView indexPathForRowAtPoint:targetContentOffset];
	CGRect rectForTopRowAfterScrolling = [tableView rectForRowAtIndexPath:indexPathOfTopRowAfterScrolling];
	targetContentOffset.y = rectForTopRowAfterScrolling.origin.y;
	
	int index = floor(targetContentOffset.y / /*CGRectGetWidth(tableView.frame))*/tableView.rowHeight);
	
	[self setupPhotoForIndex:index];
}

- (void)setupPhotoForIndex:(int)index
{
    _currentlySelectedIndex = index;
	
	if ([_dataSource respondsToSelector:@selector(photoBrowser:titleForImageAtIndex:)]) {
		self.overlayView.title = [_dataSource photoBrowser:self titleForImageAtIndex:index];
	} else {
        self.overlayView.title = @"";
    }
	
	if ([_dataSource respondsToSelector:@selector(photoBrowser:descriptionForImageAtIndex:)]) {
		self.overlayView.description = [_dataSource photoBrowser:self descriptionForImageAtIndex:index];
	} else {
        self.overlayView.description = @"";
    }
}


#pragma mark - Public methods

- (void)show
{
    //[[[UIApplication sharedApplication].windows lastObject] addSubview:self];
    self.previousWindow = [[UIApplication sharedApplication] keyWindow];
    
    self.currentWindow = [[UIWindow alloc] initWithFrame:self.previousWindow.bounds];
    self.currentWindow.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    self.currentWindow.windowLevel = UIWindowLevelStatusBar;
    self.currentWindow.hidden = NO;
    self.currentWindow.backgroundColor = [UIColor redColor];
    [self.currentWindow makeKeyAndVisible];
    [self.currentWindow addSubview:self];
    
    if ([self.dataSource respondsToSelector:@selector(canDisplayActionButtonInPhotoBrowser:)]) {
        self.overlayView.actionButton.hidden = ![self.dataSource canDisplayActionButtonInPhotoBrowser:self];
    }
	
	[UIView animateWithDuration:AGPhotoBrowserAnimationDuration
					 animations:^(){
						 self.backgroundColor = [UIColor colorWithWhite:0. alpha:1.];
						 
						 //[[UIApplication sharedApplication] setStatusBarHidden:YES];
					 }
					 completion:^(BOOL finished){
						 if (finished) {
							 self.userInteractionEnabled = YES;
							 self.displayingDetailedView = YES;
							 self.photoTableView.alpha = 1.;
							 [self.photoTableView reloadData];
						 }
					 }];
}

- (void)showFromIndex:(NSInteger)initialIndex
{
	if (initialIndex < [_dataSource numberOfPhotosForPhotoBrowser:self]) {
		[self.photoTableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:initialIndex inSection:0] atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
	}
	
	[self show];
}

- (void)hideWithCompletion:( void (^) (BOOL finished) )completionBlock
{
	[UIView animateWithDuration:AGPhotoBrowserAnimationDuration
					 animations:^(){
						 self.photoTableView.alpha = 0.;
						 self.backgroundColor = [UIColor colorWithWhite:0. alpha:0.];
						 
						 //[[UIApplication sharedApplication] setStatusBarHidden:NO];
					 }
					 completion:^(BOOL finished){
						 self.userInteractionEnabled = NO;
                         [self removeFromSuperview];
                         [self.previousWindow makeKeyAndVisible];
                         self.currentWindow.hidden = YES;
                         self.currentWindow = nil;
						 if(completionBlock) {
							 completionBlock(finished);
						 }
					 }];
}


#pragma mark - AGPhotoBrowserOverlayViewDelegate

- (void)sharingView:(AGPhotoBrowserOverlayView *)sharingView didTapOnActionButton:(UIButton *)actionButton
{
	if ([_delegate respondsToSelector:@selector(photoBrowser:didTapOnActionButton:atIndex:)]) {
		[_delegate photoBrowser:self didTapOnActionButton:actionButton atIndex:_currentlySelectedIndex];
	}
}

- (void)sharingView:(AGPhotoBrowserOverlayView *)sharingView didTapOnSeeMoreButton:(UIButton *)actionButton
{
	CGSize descriptionSize;
	if (floor(NSFoundationVersionNumber) <= NSFoundationVersionNumber_iOS_6_1) {
		descriptionSize = [sharingView.description sizeWithFont:sharingView.descriptionLabel.font constrainedToSize:CGSizeMake(CGRectGetWidth([UIScreen mainScreen].bounds) - 40, MAXFLOAT)];
	} else {
		NSDictionary *textAttributes = @{NSFontAttributeName : sharingView.descriptionLabel.font};
		CGRect descriptionBoundingRect = [sharingView.description boundingRectWithSize:CGSizeMake(CGRectGetWidth([UIScreen mainScreen].bounds) - 40, MAXFLOAT)
																			   options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading attributes:textAttributes
																			   context:nil];
		descriptionSize = CGSizeMake(ceil(CGRectGetWidth(descriptionBoundingRect)), ceil(CGRectGetHeight(descriptionBoundingRect)));
	}
	
	CGRect currentOverlayFrame = self.overlayView.frame;
	int newSharingHeight = CGRectGetHeight(currentOverlayFrame) -20 + ceil(descriptionSize.height);
	
	[UIView animateWithDuration:AGPhotoBrowserAnimationDuration
					 animations:^(){
						 self.overlayView.frame = CGRectMake(0, floor(CGRectGetHeight(self.frame) - newSharingHeight), CGRectGetWidth(self.frame), newSharingHeight);
					 }];
}


#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizerShouldBegin:(UIPanGestureRecognizer *)gestureRecognizer
{
    UIView *imageView = [gestureRecognizer view];
    CGPoint translation = [gestureRecognizer translationInView:[imageView superview]];
	
    // -- Check for horizontal gesture
    if (fabsf(translation.x) > fabsf(translation.y)) {
        return YES;
	}
	
    return NO;
}


#pragma mark - Recognizers

- (void)p_imageViewPanned:(UIPanGestureRecognizer *)recognizer
{
	AGPhotoBrowserZoomableView *imageView = (AGPhotoBrowserZoomableView *)recognizer.view;
	
	if (recognizer.state == UIGestureRecognizerStateBegan) {
        // -- Show back status bar
        [[UIApplication sharedApplication] setStatusBarHidden:NO];
		// -- Disable table view scrolling
		self.photoTableView.scrollEnabled = NO;
		// -- Hide detailed view
		self.displayingDetailedView = NO;
		_startingPanPoint = imageView.center;
		return;
	}
	
	if (recognizer.state == UIGestureRecognizerStateEnded) {
		// -- Enable table view scrolling
		self.photoTableView.scrollEnabled = YES;
		// -- Check if user dismissed the view
		CGPoint endingPanPoint = [recognizer translationInView:self];
		CGPoint translatedPoint = CGPointMake(_startingPanPoint.x - endingPanPoint.y, _startingPanPoint.y);
		int heightDifference = abs(floor(_startingPanPoint.x - translatedPoint.x));
		
		if (heightDifference <= AGPhotoBrowserThresholdToCenter) {
            
			// -- Back to original center
			[UIView animateWithDuration:AGPhotoBrowserAnimationDuration
							 animations:^(){
								 self.backgroundColor = [UIColor colorWithWhite:0. alpha:1.];
								 imageView.center = self->_startingPanPoint;
							 } completion:^(BOOL finished){
                                 // -- Hide status bar
                                 [[UIApplication sharedApplication] setStatusBarHidden:YES];
								 // -- show detailed view?
								 self.displayingDetailedView = YES;
							 }];
		} else {
			// -- Animate out!
			typeof(self) weakSelf __weak = self;
			[self hideWithCompletion:^(BOOL finished){
				typeof(weakSelf) strongSelf __strong = weakSelf;
				if (strongSelf) {
					imageView.center = strongSelf->_startingPanPoint;
				}
			}];
		}
	} else {
		CGPoint middlePanPoint = [recognizer translationInView:self];
		CGPoint translatedPoint = CGPointMake(_startingPanPoint.x - middlePanPoint.y, _startingPanPoint.y);
		imageView.center = translatedPoint;
		int heightDifference = abs(floor(_startingPanPoint.x - translatedPoint.x));
		CGFloat ratio = (_startingPanPoint.x - heightDifference)/_startingPanPoint.x;
		self.backgroundColor = [UIColor colorWithWhite:0. alpha:ratio];
	}
}


#pragma mark - Private methods

- (void)p_doneButtonTapped:(UIButton *)sender
{
	if ([_delegate respondsToSelector:@selector(photoBrowser:didTapOnDoneButton:)]) {
		self.displayingDetailedView = NO;
		[_delegate photoBrowser:self didTapOnDoneButton:sender];
	}
}


#pragma mark - Orientation change

- (void)statusBarDidChangeFrame:(NSNotification *)notification
{
    UIDeviceOrientation orientation = [[UIDevice currentDevice] orientation];
    CGFloat angle = UIInterfaceOrientationAngleOfOrientation(orientation);
    CGAffineTransform viewTransform = CGAffineTransformMakeRotation(angle);
    CGRect frame = self.currentWindow.bounds;
    
    [self setIfNotEqualTransform:viewTransform frame:frame];
    [self setNeedsUpdateConstraints];
    NSLog(@"Window frame %@", NSStringFromCGRect(self.currentWindow.frame));
    NSLog(@"View frame %@", NSStringFromCGRect(self.frame));
    NSLog(@"Table frame %@", NSStringFromCGRect(self.photoTableView.frame));
    [self.photoTableView reloadData];
}

- (void)setIfNotEqualTransform:(CGAffineTransform)transform frame:(CGRect)frame
{
    if (!CGAffineTransformEqualToTransform(self.transform, transform)) {
        self.transform = transform;
    }
    if (!CGRectEqualToRect(self.frame, frame)) {
        self.frame = frame;
    }
}

- (void)setTableIfNotEqualTransform:(CGAffineTransform)transform
{
    if(!CGAffineTransformEqualToTransform(self.photoTableView.transform, transform)) {
        self.photoTableView.transform = transform;
    }
}

CGFloat UIInterfaceOrientationAngleOfOrientation(UIDeviceOrientation orientation)
{
    CGFloat angle;
    
    switch (orientation) {
        case UIDeviceOrientationPortraitUpsideDown:
            angle = M_PI;
            break;
        case UIDeviceOrientationLandscapeLeft:
            angle = -M_PI_2;
            break;
        case UIDeviceOrientationLandscapeRight:
            angle = M_PI_2;
            break;
        default:
            angle = M_PI;
            break;
    }
    
    return angle;
}

@end
