//
//  MasterViewController.swift
//  Timely2
//
//  Created by Mihai Leonte on 5/25/18.
//  Copyright © 2018 Mihai Leonte. All rights reserved.
//

import UIKit



class StoriesMasterViewController: UITableViewController {
    
    @IBOutlet weak var errorView: UIView!
    @IBOutlet weak var errorLabel: UILabel!
    @IBOutlet weak var emptyView: UIView!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var loadingView: UIView!
    @IBOutlet var tapGesture: UITapGestureRecognizer!
    @IBOutlet weak var feedButton: UIBarButtonItem!
    @IBOutlet var feedPopoverView: UIView!
    @IBOutlet weak var visualBlurEffectView: UIVisualEffectView!
    @IBOutlet weak var feedTableView: UITableView!
    @IBOutlet weak var headerTitle: UINavigationItem!
    
    @IBAction func tapBlurEffectView(_ sender: Any) {
        self.feedSelectionViewIsOpen.toggle()
        closePopoverView()
    }
    
    var storiesDataSource: StoriesDataSource? = nil
    var feedDataSource: FeedDataSource? = nil
    
    var blurEffectView: UIView = UIView()
    var detailViewController: StoriesDetailViewController? = nil
    var myRefreshControl: UIRefreshControl?
    
    
    var state = State.loading {
        didSet {
            print(state)
            setFooterView()
            
            // Refresh DataSource
            storiesDataSource?.setData(sourceAPI: currentSourceAPI, stories: topStories, algoliaStories: algoliaStories)
            
            // Reload Table View and scrolls to first row
            tableView.scrollToFirst()
        }
    }
    
    var topStories: [Item] = []
    var algoliaStories: [AlgoliaItem] = []
    var feedSelectionViewIsOpen: Bool = false
    
    let defaults = UserDefaults.standard
    var currentSourceAPI: HNFeedType = .official
    var currentSelectedFeedURL = URLComponents(string: "https://hacker-news.firebaseio.com/v0/topstories.json")!
    var currentSelectedFeedTitle = "HN Top Stories"
    var myFeeds: [Feed] = []

    let configuration = URLSessionConfiguration.default
    var defaultSession: URLSession = URLSession(configuration: .default)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // DataSource Configuration
        storiesDataSource = StoriesDataSource()
        storiesDataSource?.delegate = self
        self.tableView.dataSource = storiesDataSource
        storiesDataSource?.setData(sourceAPI: currentSourceAPI, stories: topStories, algoliaStories: algoliaStories)
        
        // Don't use the URLSession.shared as calling invalidateAndCancel() on the session returned by the shared method has no effect.
        self.configuration.waitsForConnectivity = true
        self.defaultSession = URLSession(configuration: configuration)
        
        activityIndicator.color = UIColor.lightGray
        
        //Feed Selection Setup
        myFeeds = loadFeedsFromFile()
        setFeedTableView(with: myFeeds)
        customizeFeedPopoverView()
        
        setUpPullToRefresh()
        
        if let split = splitViewController {
            let controllers = split.viewControllers
            detailViewController = (controllers[controllers.count-1] as! UINavigationController).topViewController as? StoriesDetailViewController
        }
        self.tableView.estimatedRowHeight = 100
        self.tableView.rowHeight = UITableViewAutomaticDimension
        
        
        loadDefaultFeed()
        updateStories()
        
    }
    
    /// Loads Feed data from FeedList.plist and parses it in an array of Feed type.
    ///
    /// - Returns: a Feed array
    func loadFeedsFromFile() -> [Feed] {
        var myFeeds: [Feed] = []
        if let feedListURL = Bundle.main.url(forResource: "FeedList", withExtension: "plist") {
            do {
                let feedListData = try Data(contentsOf: feedListURL)
                let plistDecoder = PropertyListDecoder()
                myFeeds = try plistDecoder.decode([Feed].self, from: feedListData)
            } catch {
                print(error)
            }
        }
        return myFeeds.filter { $0.isHidden == false }
    }
    
    /// Sets up a new TableView to select the Feed/Sort option.
    ///
    /// - Parameter feed: the [Feed] object - FeedList.plist parsed
    func setFeedTableView(with feed: [Feed]) {
        feedDataSource = FeedDataSource()
        feedDataSource?.setData(feedList: feed)
        feedDataSource?.cellDelegate = self
        
        //Set height of the Feed Select tableview to be set automatic (based on the number of rows)
        let tableHeight = self.feedTableView.rowHeight * CGFloat(feed.count) + self.feedTableView.sectionHeaderHeight
        self.feedTableView.translatesAutoresizingMaskIntoConstraints = false
        self.feedTableView.heightAnchor.constraint(equalToConstant: tableHeight).isActive = true
        
        self.feedTableView.layer.borderColor = UIColor.lightGray.cgColor
        self.feedTableView.layer.borderWidth = 1
        
        self.feedTableView.dataSource = feedDataSource
        self.feedTableView.delegate = feedDataSource
        self.feedTableView.register(FeedCell.self, forCellReuseIdentifier: "TableViewCell")
        
        //self.tapGesture.delegate = self
    }
    
    /// Sets up the Popover View which contains the Feed/Sort TableView.
    func customizeFeedPopoverView() {
        
        self.view.addSubview(feedPopoverView)
        feedPopoverView.translatesAutoresizingMaskIntoConstraints = false
        feedPopoverView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor).isActive = true
        feedPopoverView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor).isActive = true
        feedPopoverView.rightAnchor.constraint(equalTo: view.safeAreaLayoutGuide.rightAnchor).isActive = true
        feedPopoverView.leftAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leftAnchor).isActive = true
        //feedPopoverView.heightAnchor.constraint(equalToConstant: 600).isActive = true
        //feedPopoverView.widthAnchor.constraint(equalToConstant: 400).isActive = true
        
        feedTableView.layer.cornerRadius = 8.0
        feedTableView.clipsToBounds = true
    }
    
    /// Load The Previously Selected Feed ID from Userdefaults and load data from Feed List (in order to recreate updated timestamps)
    func loadDefaultFeed() {
        
        var feedID = defaults.integer(forKey: "feedID")
        
        //defaults.integer(forKey: "feedID") will return 0 if the value is not found
        if feedID == 0 {
            feedID = 1
        }
        
        let selectedFeed = myFeeds.filter { $0.feedID == feedID }[0]
        let feedType = selectedFeed.feedType
        
        let feedURLstring = selectedFeed.feedURL
        guard var feedURLComponents = URLComponents(string: feedURLstring) else {
            return
        }
        
        if feedType == .algolia {
            if let feedFromCalendarComponentByAdding = selectedFeed.fromCalendarComponentByAdding {
                if let feedFromCalendarComponentValue = selectedFeed.fromCalendarComponentValue {
                    let currentTimestamp = Int(NSDate().timeIntervalSince1970)
                    let today = Date()
                    let priorDate = Calendar.current.date(byAdding: feedFromCalendarComponentByAdding, value: feedFromCalendarComponentValue, to: today)
                    let priorTimestamp = Int(priorDate!.timeIntervalSince1970)
                    
                    let queryItemTimeRange = URLQueryItem(name: "numericFilters", value: "created_at_i>\(priorTimestamp),created_at_i<\(currentTimestamp)")
                    
                    feedURLComponents.addOrModify(queryItemTimeRange)
                }
            }
        }
        
        currentSourceAPI = feedType
        currentSelectedFeedTitle = selectedFeed.feedName
        currentSelectedFeedURL = feedURLComponents
    }
    
    
    /// Initiate updating the Stories TableView based on the currently selected Feed (title, feedType/currentSourceAPI and feedURL)
    func updateStories() {
        self.headerTitle.title = currentSelectedFeedTitle
        
        switch currentSourceAPI {
        case .official:
            fetchStoryIDs(from: currentSelectedFeedURL)
        case .timely:
            fetchStoryIDs(from: currentSelectedFeedURL)
        case .algolia:
            fetchAlgoliaStories(from: currentSelectedFeedURL)
        }
        
        self.state = .loading
    }
    
    /// Sets up Pull To Refresh - and calls refreshData()
    func setUpPullToRefresh() {
        myRefreshControl = UIRefreshControl()
        myRefreshControl?.addTarget(self, action: #selector(refreshData(sender:)), for: .valueChanged)
        myRefreshControl?.attributedTitle = NSAttributedString(string: "Pull to refresh")
        self.tableView.refreshControl = myRefreshControl
    }
    
    // FIXME: Defect use Refresh Control animation instead of the state.loading animation
    @objc func refreshData(sender: UIRefreshControl) {
        
        switch self.currentSourceAPI {
        case .official:
            fetchStoryIDs(from: self.currentSelectedFeedURL)
        case .timely:
            fetchStoryIDs(from: self.currentSelectedFeedURL)
        case .algolia:
            fetchAlgoliaStories(from: self.currentSelectedFeedURL)
        }
        
        sender.endRefreshing()
    }
    
    // feedButton pressed
    @IBAction func changeFeed(_ sender: Any) {
        
        self.feedSelectionViewIsOpen.toggle()
        
        if feedSelectionViewIsOpen {
            self.feedButton.image = nil
            self.feedButton.title = "Cancel"
            
            // Fade in the Transluscent View (Feed Selection)
            self.feedPopoverView.alpha = 0.0
            self.feedPopoverView.isHidden = false
            UIView.animate(withDuration: 0.2) {
                self.feedPopoverView.alpha = 1.0
            }
            
            //self.tableView.isUserInteractionEnabled = false
            //self.feedPopoverView.isUserInteractionEnabled = true
        } else {
            closePopoverView()
        }
    }
    
    func closePopoverView() {
        self.feedButton.image = UIImage(named: "icn_feedSelect")
        self.feedButton.title = nil
        
        self.feedPopoverView.isHidden = true

        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        
        if let index = self.tableView.indexPathForSelectedRow{
            self.tableView.deselectRow(at: index, animated: true)
        }
    }
    
    func fetchAlgoliaStories(from urlComponents: URLComponents) {
        
        self.topStories.removeAll()
        self.state = .loading
        
        if let url = urlComponents.url {
        
            _ = self.defaultSession.dataTask(with: url) { responseData, response, error in
                
                    if let error = error {
                        self.state = .error(error)
                        return
                    }
                
                    guard let httpResponse = response as? HTTPURLResponse,
                        (200...299).contains(httpResponse.statusCode) else {
                            // FIXME: add response status code
                            self.state = .error(HNError.network(""))
                            return
                    }
                
                    if let mimeType = httpResponse.mimeType, mimeType == "application/json", let data = responseData {
                        //print("JSON String: \(String(data: data, encoding: .utf8))")
                        
                        do {
                            let decoder = JSONDecoder()
                            decoder.dateDecodingStrategy = .customISO8601
                            let stories = try decoder.decode(AlgoliaItemList.self, from: data)
                            
                            DispatchQueue.main.async {
                                self.algoliaStories = stories.hits
                                self.state = .populated
                                //self.tableView.reloadData()
                            }
                        } catch let error {
                            self.state = .error(HNError.parsingJSON(error.localizedDescription))
                        }
                    }
            }.resume()
        }
    }
    
    // Official API
    func fetchStoryIDs(from urlComponents: URLComponents) {
        self.topStories.removeAll()
        self.state = .loading
        
        if let url = urlComponents.url {
        
            let task = self.defaultSession.dataTask(with: url) { data, response, error in
                // TODO - could this be moved only on the reload of the tableView?
                DispatchQueue.main.async {
                    if let error = error {
                        self.state = .error(error)
                        return
                    }
                    
                    guard let httpResponse = response as? HTTPURLResponse,
                        (200...299).contains(httpResponse.statusCode) else {
                            self.state = .error(HNError.network(""))
                            return
                    }
                    
                    if let mimeType = httpResponse.mimeType, mimeType == "application/json", let data = data {
                        do {
                            let decoder = JSONDecoder()
                            let stories = try decoder.decode([Int].self, from: data)
                            
                            for storyId in stories.prefix(20) {
                                self.topStories.append(Item(id: storyId))
                            }
                            
                            self.state = .populated
                            //self.tableView.reloadData()
                            self.fetchItems()
                            
                        } catch let error {
                            self.state = .error(HNError.parsingJSON(error.localizedDescription))
                        }
                    }
                }
            }
            task.resume()
        }
    }

    // Official API
    func fetchItems() {

        for (index, item) in self.topStories.enumerated() {
            
            self.topStories[index].state = .downloading
            
            // Construct the URLRequest
            let itemID = String(item.id)
            let urlString = "https://hacker-news.firebaseio.com/v0/item/\(itemID).json"
            let requestItem = URLRequest(url: URL(string: urlString)!)
            
            let taskItem = self.defaultSession.dataTask(with: requestItem) { data, response, error in
                
                if let data = data, let response = response as? HTTPURLResponse {
                    let statusCode = response.statusCode
                    if statusCode == 200 {
                        //print("200 OK on Item ID = \(itemID)")
                        
                        self.topStories[index].state = .downloaded
                        //print(data)
                    
                        do {
                            let decoder = JSONDecoder()
                            decoder.dateDecodingStrategy = .secondsSince1970
                            let story = try decoder.decode(Item.self, from: data)

                            guard story.deleted == nil else {
                                print("Deleted HN Item \(itemID) was ignored")
                                return
                            }
                            
                            guard story.type == .story else {
                                print("HN Item \(itemID) was ignored because it was not a story type.")
                                return
                            }
                            
                            self.topStories[index].title = story.title
                            self.topStories[index].url = story.url
                            self.topStories[index].by = story.by
                            self.topStories[index].descendants = story.descendants
                            self.topStories[index].score = story.score
                            self.topStories[index].time = story.time
                            self.topStories[index].kids = story.kids
                            //print(story.kids)
                            DispatchQueue.main.async {
                                //reloadRows has an expected argument type of [IndexPath]
                                self.tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .fade)
                            }
                        }
                        catch let error {
                            print("Could not convert JSON data into a dictionary. Error: " + error.localizedDescription)
                            print(error)
                            self.topStories[index].state = .failed
                            DispatchQueue.main.async {
                                self.tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .fade)
                            }
                        }
                    }
                }
                
            }
            taskItem.resume()
        }
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }


    
    // MARK: - Segues
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "showDetail" {
            if let indexPath = tableView.indexPathForSelectedRow {
                
                let controller = (segue.destination as! UINavigationController).topViewController as! StoriesDetailViewController
                switch currentSourceAPI {
                case .official:
                    let selectedItem = topStories[indexPath.row]
                    controller.detailItem = selectedItem
                case .algolia, .timely:
                    let selectedItem = algoliaStories[indexPath.row]
                    controller.algoliaItem = selectedItem
                }
                
                controller.navigationItem.leftBarButtonItem = splitViewController?.displayModeButtonItem
                controller.navigationItem.leftItemsSupplementBackButton = true
            }
        }
    }
    
    
    func setFooterView() {
        
        switch state {
            
        case .error(let error):
            errorLabel.text = error.localizedDescription
            tableView.tableFooterView = errorView
        case .loading:
            tableView.tableFooterView = loadingView
//      case .paging:
//          tableView.tableFooterView = loadingView
        case .empty:
            tableView.tableFooterView = emptyView
        case .populated:
            tableView.tableFooterView = nil
        }
        
    }
}

extension StoriesMasterViewController: StoriesDataSourceDelegate {
    func updateState(_ newState: State) {
        self.state = newState
    }
}

// A new Feed was Selected from the Feed Selection View Controller
extension StoriesMasterViewController: CellFeedProtocol {
    func didTapCell(feedURL: URLComponents, title: String, type: HNFeedType) {
        
        //Cancel all existing requests which are in progress
        self.defaultSession.getTasksWithCompletionHandler{ dataTasks, uploadTasks, downloadTasks in
            for task in dataTasks {
                task.cancel()
            }
        }
        
        //Close the Feed Selection popup
        self.feedSelectionViewIsOpen.toggle()
        closePopoverView()
        
        //Fetch the new stories for the new Feed & Update the TableView
        self.currentSelectedFeedTitle = title
        self.currentSourceAPI = type
        self.currentSelectedFeedURL = feedURL
        updateStories()
    }
    
}
