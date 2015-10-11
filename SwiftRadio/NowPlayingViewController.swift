//
//  NowPlayingViewController.swift
//  Swift Radio
//
//  Created by Matthew Fecher on 7/22/15.
//  Copyright (c) 2015 MatthewFecher.com. All rights reserved.
//
//  Modified October 2015 to use StormyProductions RadioKit for improved stream handling
//  NOTE: RadioKit is an streaming library that requires a license key if used
//       in a product.  For more information, see: http://www.stormyprods.com/products/radiokit.php


import UIKit
import MediaPlayer

//*****************************************************************
// Protocol
// Updates the StationsViewController when the track changes
//*****************************************************************

protocol NowPlayingViewControllerDelegate: class {
    func songMetaDataDidUpdate(track: Track)
    func artworkDidUpdate(track: Track)
}

//*****************************************************************
// NowPlayingViewController
//*****************************************************************

class NowPlayingViewController: UIViewController {

    @IBOutlet weak var albumHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var albumImageView: SpringImageView!
    @IBOutlet weak var artistLabel: UILabel!
    @IBOutlet weak var pauseButton: UIButton!
    @IBOutlet weak var playButton: UIButton!
    @IBOutlet weak var rewButton: UIButton!
    @IBOutlet weak var ffButton: UIButton!
    @IBOutlet weak var songLabel: SpringLabel!
    @IBOutlet weak var stationDescLabel: UILabel!
    @IBOutlet weak var volumeParentView: UIView!
    @IBOutlet weak var slider = UISlider()
    @IBOutlet weak var bufferView: BufferView!
    
    var currentStation: RadioStation!
    var downloadTask: NSURLSessionDownloadTask?
    var iPhone4 = false
    var justBecameActive = false
    var newStation = true
    var nowPlayingImageView: UIImageView!
    let radioPlayer = Player.radio
    var track: Track!
    var mpVolumeSlider = UISlider()
    
    var rewOrFFTimer = NSTimer()
    var bufferViewTimer = NSTimer()
    
    weak var delegate: NowPlayingViewControllerDelegate?
    
    //*****************************************************************
    // MARK: - ViewDidLoad
    //*****************************************************************
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set AlbumArtwork Constraints
        optimizeForDeviceSize()

        // Set View Title
        self.title = currentStation.stationName
        
        // Create Now Playing BarItem
        createNowPlayingAnimation()
        
        // Setup RadioKit library
        setupPlayer()
        
        // Notification for when app becomes active
        NSNotificationCenter.defaultCenter().addObserver(self,
            selector: "didBecomeActiveNotificationReceived",
            name:"UIApplicationDidBecomeActiveNotification",
            object: nil)
        
        // Notification for MediaPlayer metadata updated
        NSNotificationCenter.defaultCenter().addObserver(self,
            selector: Selector("metadataUpdated:"),
            name:MPMoviePlayerTimedMetadataUpdatedNotification,
            object: nil);
        
        // Check for station change
        if newStation {
            track = Track()
            stationDidChange()
        } else {
            updateLabels()
            albumImageView.image = track.artworkImage
            
            if !track.isPlaying {
                pausePressed()
            } else {
                nowPlayingImageView.startAnimating()
            }
        }
        
        // Setup slider
        setupVolumeSlider()
        
        startBufferViewThread()
    }
    
    func didBecomeActiveNotificationReceived() {
        // View became active
        updateLabels()
        justBecameActive = true
        updateAlbumArtwork()
    }
    
    deinit {
        // Be a good citizen
        NSNotificationCenter.defaultCenter().removeObserver(self,
            name:"UIApplicationDidBecomeActiveNotification",
            object: nil)
        NSNotificationCenter.defaultCenter().removeObserver(self,
            name: MPMoviePlayerTimedMetadataUpdatedNotification,
            object: nil)
    }
    
    //*****************************************************************
    // MARK: - Setup
    //*****************************************************************
    
    func setupPlayer() {
        // We only need to perform these setup operations once for the lifetime of the app
        struct Onceler{
            static var doOnce = true
        }
        
        if (Onceler.doOnce){
            Onceler.doOnce = false

            //TODO: Enter you RadioKit license key information here.
            radioPlayer.authenticateLibraryWithKey1(0x1, andKey2: 0x02)
            radioPlayer.delegate = self
            if DEBUG_LOG {
                print("RadioKit version: \(radioPlayer.version())")
            }
        }
    }
  
    func setupVolumeSlider() {
        // Note: This slider implementation uses a MPVolumeView
        // The volume slider only works in devices, not the simulator.
  
        volumeParentView.backgroundColor = UIColor.clearColor()
        let volumeView = MPVolumeView(frame: volumeParentView.bounds)
        for view in volumeView.subviews {
            let uiview: UIView = view as UIView
             if (uiview.description as NSString).rangeOfString("MPVolumeSlider").location != NSNotFound {
                mpVolumeSlider = (uiview as! UISlider)
            }
        }
        
        let thumbImageNormal = UIImage(named: "slider-ball")
        slider?.setThumbImage(thumbImageNormal, forState: .Normal)
        
    }
    
    func stationDidChange() {
        radioPlayer.stopStream()
        
        radioPlayer.setStreamUrl(currentStation.stationStreamURL, isFile: false)
        radioPlayer.startStream()
        
        updateLabels("Loading Station...")
        
        // songLabel animate
        songLabel.animation = "flash"
        songLabel.repeatCount = 2
        songLabel.animate()
        
        resetAlbumArtwork()
        
        track.isPlaying = true
    }
    
    //*****************************************************************
    // MARK: - Player Controls (Play/Pause/Volume)
    //*****************************************************************
    
    @IBAction func playPressed() {
        track.isPlaying = true
        playButtonEnable(false)
        radioPlayer.startStream()
        updateLabels()
        
        // songLabel Animation
        songLabel.animation = "flash"
        songLabel.animate()
        
        // Start NowPlaying Animation
        nowPlayingImageView.startAnimating()
    }
    
    @IBAction func pausePressed() {
        track.isPlaying = false
        
        playButtonEnable()
        
        radioPlayer.pauseStream()
        nowPlayingImageView.stopAnimating()
    }
    
    @IBAction func volumeChanged(sender:UISlider) {
        mpVolumeSlider.value = sender.value
    }
    
    func rewind()
    {
        radioPlayer.rewind(10)		  // Rewind 10 seconds
        dispatch_async(dispatch_get_main_queue(), {
            self.updateAudioButtons()
        })
    }
    
    @IBAction func rewindDown()
    {
        rewind()
        rewOrFFTimer = NSTimer.scheduledTimerWithTimeInterval(0.3, target:self, selector:"rewind", userInfo:nil, repeats:true)
    }
    
    
    @IBAction func rewindUp()
    {
        rewOrFFTimer.invalidate();
    }
    
    func fastForward()
    {
        radioPlayer.fastForward(10)
        dispatch_async(dispatch_get_main_queue(), {
            self.updateAudioButtons()
        })
    }
    
    
    @IBAction func fastForwardDown()
    {
        fastForward()
        rewOrFFTimer = NSTimer.scheduledTimerWithTimeInterval(0.3, target:self, selector:"fastForward", userInfo:nil, repeats:true)
    }
    
    
    @IBAction func fastForwardUp()
    {
        rewOrFFTimer.invalidate()
    }
    
    
    func bufferVisualThread()
    {
        bufferView.bufferSizeSRK = radioPlayer.maxBufferSize()
        bufferView.bufferCountSRK = radioPlayer.currBufferUsage()
        bufferView.currBuffPtr = radioPlayer.currBufferPlaying()
        bufferView.bufferByteOffset = radioPlayer.bufferByteOffset()
        
        dispatch_async(dispatch_get_main_queue(), {
            self.bufferView.setNeedsDisplay()})
    }

    func startBufferViewThread()
    {
        bufferViewTimer = NSTimer.scheduledTimerWithTimeInterval(0.2, target:self, selector:"bufferVisualThread", userInfo:nil, repeats:true)
    }
    
    
    func stopBufferViewThread()
    {
        bufferViewTimer.invalidate()
    }
    
    //*****************************************************************
    // MARK: - UI Helper Methods
    //*****************************************************************
    
    func optimizeForDeviceSize() {
        
        // Adjust album size to fit iPhone 4s & iPhone 6 & 6+
        let deviceHeight = self.view.bounds.height
        
        if deviceHeight == 480 {
            iPhone4 = true
            albumHeightConstraint.constant = 106
            view.updateConstraints()
        } else if deviceHeight == 667 {
            albumHeightConstraint.constant = 230
            view.updateConstraints()
        } else if deviceHeight > 667 {
            albumHeightConstraint.constant = 260
            view.updateConstraints()
        }
    }
    
    func updateLabels(statusMessage: String = "") {
        
        if statusMessage != "" {
            // There's a an interruption or pause in the audio queue
            songLabel.text = statusMessage
            artistLabel.text = currentStation.stationName
            
        } else {
            // Radio is (hopefully) streaming properly
            if track != nil {
                songLabel.text = track.title
                artistLabel.text = track.artist
            }
        }
        
        // Hide station description when album art is displayed or on iPhone 4
        if track.artworkLoaded || iPhone4 {
            stationDescLabel.hidden = true
        } else {
            stationDescLabel.hidden = false
            stationDescLabel.text = currentStation.stationDesc
        }
    }
    
    func playButtonEnable(enabled: Bool = true) {
        if enabled {
            playButton.enabled = true
            pauseButton.enabled = false
            track.isPlaying = false
        } else {
            playButton.enabled = false
            pauseButton.enabled = true
            track.isPlaying = true
        }
        updateAudioButtons()
    }

    func updateAudioButtons() {
            // Check if the stream is currently playing.  If so, adjust the play control buttons
            if (track.isPlaying){
                    rewButton.enabled = true
                    
                    if (radioPlayer.isFastForwardAllowed(10)){
                        ffButton.enabled = true
                    }else{
                        ffButton.enabled = false
                    }
            }else{
                rewButton.enabled = false
                ffButton.enabled = false
            }
    }

    
    func createNowPlayingAnimation() {
        
        // Setup ImageView
        nowPlayingImageView = UIImageView(image: UIImage(named: "NowPlayingBars-3"))
        nowPlayingImageView.autoresizingMask = UIViewAutoresizing.None
        nowPlayingImageView.contentMode = UIViewContentMode.Center
        
        // Create Animation
        nowPlayingImageView.animationImages = AnimationFrames.createFrames()
        nowPlayingImageView.animationDuration = 0.7
        
        // Create Top BarButton
        let barButton = UIButton(type: UIButtonType.Custom)
        barButton.frame = CGRectMake(0, 0, 40, 40);
        barButton.addSubview(nowPlayingImageView)
        nowPlayingImageView.center = barButton.center
        
        let barItem = UIBarButtonItem(customView: barButton)
        self.navigationItem.rightBarButtonItem = barItem
        
    }
    
    func startNowPlayingAnimation() {
        nowPlayingImageView.startAnimating()
    }
    
    //*****************************************************************
    // MARK: - Album Art
    //*****************************************************************
    
    func resetAlbumArtwork() {
        track.artworkLoaded = false
        track.artworkURL = currentStation.stationImageURL
        updateAlbumArtwork()
        stationDescLabel.hidden = false
    }
    
    func updateAlbumArtwork() {
        
        if track.artworkURL.rangeOfString("http") != nil {
            
            // Hide station description
            dispatch_async(dispatch_get_main_queue()) {
                self.stationDescLabel.hidden = true
            }
            
            // Attempt to download album art from LastFM
            if let url = NSURL(string: track.artworkURL) {
                
                self.downloadTask = self.albumImageView.loadImageWithURL(url) {
                    (image) in
                    
                    // Update track struct
                    self.track.artworkImage = image
                    self.track.artworkLoaded = true
                    
                    // Turn off network activity indicator
                    UIApplication.sharedApplication().networkActivityIndicatorVisible = false
                        
                    // Animate artwork
                    self.albumImageView.animation = "wobble"
                    self.albumImageView.duration = 2
                    self.albumImageView.animate()
                    
                    // Update lockscreen
                    self.updateLockScreen()
                    
                    // Call delegate function that artwork updated
                    self.delegate?.artworkDidUpdate(self.track)
                }
            }
            
            // Hide the station description to make room for album art
            if track.artworkLoaded && !self.justBecameActive {
                self.stationDescLabel.hidden = true
                self.justBecameActive = false
            }
            
        } else if track.artworkURL != "" {
            // Local artwork
            self.albumImageView.image = UIImage(named: track.artworkURL)
            track.artworkImage = albumImageView.image
            track.artworkLoaded = true
            
            // Call delegate function that artwork updated
            self.delegate?.artworkDidUpdate(self.track)
            
        } else {
            // No Station or LastFM art found, use default art
            self.albumImageView.image = UIImage(named: "albumArt")
            track.artworkImage = albumImageView.image
        }
        
        // Force app to update display
        self.view.setNeedsDisplay()
    }

    // Call LastFM API to get album art url
    
    func queryAlbumArt() {
        
        UIApplication.sharedApplication().networkActivityIndicatorVisible = true
        
        // Construct LastFM API Call URL
        let queryURL = String(format: "http://ws.audioscrobbler.com/2.0/?method=track.getInfo&api_key=%@&artist=%@&track=%@&format=json", apiKey, track.artist, track.title)
        
        let escapedURL = queryURL.stringByAddingPercentEncodingWithAllowedCharacters(NSCharacterSet.URLQueryAllowedCharacterSet())
        
        // Query API
        DataManager.getTrackDataWithSuccess(escapedURL!) { (data) in
            
            // Turn on network indicator in status bar
            UIApplication.sharedApplication().networkActivityIndicatorVisible = false
            
            if DEBUG_LOG {
                print("LAST FM API SUCCESSFUL RETURN")
                print("url: \(escapedURL!)")
            }
            
            let json = JSON(data: data)
            
            // Get Largest Sized Image
            if let imageArray = json["track"]["album"]["image"].array {
                
                let arrayCount = imageArray.count
                let lastImage = imageArray[arrayCount - 1]
                
                if let artURL = lastImage["#text"].string {
                    
                    UIApplication.sharedApplication().networkActivityIndicatorVisible = true
                    
                    // Check for Default Last FM Image
                    if artURL.rangeOfString("/noimage/") != nil {
                        self.resetAlbumArtwork()
                        
                    } else {
                        // LastFM image found!
                        self.track.artworkURL = artURL
                        self.track.artworkLoaded = true
                        self.updateAlbumArtwork()
                    }
                    
                } else {
                    self.resetAlbumArtwork()
                }
            } else {
                self.resetAlbumArtwork()
            }
        }
    }
    
    //*****************************************************************
    // MARK: - Segue
    //*****************************************************************
    
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        
        if segue.identifier == "InfoDetail" {
            let infoController = segue.destinationViewController as! InfoDetailViewController
            infoController.currentStation = currentStation
        }
    }
    
    @IBAction func infoButtonPressed(sender: UIButton) {
        performSegueWithIdentifier("InfoDetail", sender: self)
    }
    
    //*****************************************************************
    // MARK: - MPNowPlayingInfoCenter (Lock screen)
    //*****************************************************************
    
    func updateLockScreen() {
        
        // Update notification/lock screen
        let albumArtwork = MPMediaItemArtwork(image: track.artworkImage!)
        
        MPNowPlayingInfoCenter.defaultCenter().nowPlayingInfo = [
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtwork: albumArtwork
        ]
    }
    
    override func remoteControlReceivedWithEvent(receivedEvent: UIEvent?) {
        super.remoteControlReceivedWithEvent(receivedEvent)
        
        if receivedEvent!.type == UIEventType.RemoteControl {
            
            switch receivedEvent!.subtype {
            case .RemoteControlPlay:
                playPressed()
            case .RemoteControlPause:
                pausePressed()
            default:
                break
            }
        }
    }
    
    // MARK Stormy RadioKit (SRK) protocol handlers
    
    //*****************************************************************
    // MARK: - MetaData Updated Notification
    //*****************************************************************
    
    func SRKMetaChanged()
    {
        if(radioPlayer.currTitle != nil)
        {
            startNowPlayingAnimation()
            
            let metaData = radioPlayer.currTitle as String
            
            var stringParts = [String]()
            if metaData.rangeOfString(" - ") != nil {
                stringParts = metaData.componentsSeparatedByString(" - ")
            } else {
                stringParts = metaData.componentsSeparatedByString("-")
            }
            
            // Set artist & songvariables
            let currentSongName = track.title
            track.artist = stringParts[0]
            track.title = stringParts[0]
            
            if stringParts.count > 1 {
                track.title = stringParts[1]
            }
            
            if track.artist == "" && track.title == "" {
                track.artist = currentStation.stationDesc
                track.title = currentStation.stationName
            }
            
            dispatch_async(dispatch_get_main_queue()) {
                
                if currentSongName != self.track.title {
                    
                    if DEBUG_LOG {
                        print("METADATA artist: \(self.track.artist) | title: \(self.track.title)")
                    }
                    
                    // Update Labels
                    self.artistLabel.text = self.track.artist
                    self.songLabel.text = self.track.title
                    
                    // songLabel animation
                    self.songLabel.animation = "zoomIn"
                    self.songLabel.duration = 1.5
                    self.songLabel.damping = 1
                    self.songLabel.animate()
                    
                    // Update Stations Screen
                    self.delegate?.songMetaDataDidUpdate(self.track)
                    
                    // Query LastFM API for album art
                    self.resetAlbumArtwork()
                    self.queryAlbumArt()
                    self.updateLockScreen()
                    
                }
            }
        }
    }
    
    func SRKConnecting()
    {
        dispatch_async(dispatch_get_main_queue(), {
            self.updateLabels("Connecting to Station...")
        })
    }
    
    func SRKIsBuffering()
    {
        dispatch_async(dispatch_get_main_queue(), {
            self.updateLabels("Buffering...")
        })
    }
    
    func SRKPlayStarted()
    {
        dispatch_async(dispatch_get_main_queue(), {
            self.updateLabels()
            self.playButtonEnable(false)
        })
    }
    
    func SRKPlayStopped()
    {
        dispatch_async(dispatch_get_main_queue(), {
            self.playButtonEnable(true)})
    }
    
    func SRKPlayPaused()
    {
        dispatch_async(dispatch_get_main_queue(), {
            self.playButtonEnable(true)
            self.updateLabels("Station Paused...")
        })
    }
    
    func SRKNoNetworkFound()
    {
        
    }


}
