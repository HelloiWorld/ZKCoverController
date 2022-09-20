//
//  AppDelegate.swift
//  ZKCoverController
//
//  Created by pengzhangkun on 2022/9/19.
//

import Foundation
import UIKit

protocol ZKCoverControllerDataSource: NSObjectProtocol {
    /// 获取上一个控制器
    func coverController(_ coverController: ZKCoverController, getAboveController currentController: UIViewController?) -> UIViewController?
    /// 获取下一个控制器
    func coverController(_ coverController: ZKCoverController, getBelowController currentController: UIViewController?) -> UIViewController?
}

protocol ZKCoverControllerDelegate: NSObjectProtocol {
    /// 切换是否完成
    func coverController(_ coverController: ZKCoverController, currentController: UIViewController?, finish isFinish: Bool)
    /// 拖拽手势触发前
    func coverController(_ coverController: ZKCoverController, gestureRecognizerShouldBegin gestureRecognizer: UIGestureRecognizer) -> Bool
    /// 拖拽手势响应事件
    func touchPan(_ pan: UIPanGestureRecognizer)
}

// TODO: Feature
// 1、临时控制器以后应该放在一个集合中，同时允许多个动画层现，然后在页面消失时移除
// 2、向某个方向动画过程中不应该接收反方向的动画，应直接忽略
class ZKCoverController: UIViewController {
    
    weak var dataSource: ZKCoverControllerDataSource?
    weak var delegate: ZKCoverControllerDelegate?
    
    /// 正在动画
    private(set) var isAnimateChange: Bool = false
    /// 当前展示的控制器
    weak var currentController: UIViewController?
    /// 临时控制器
    private(set) var tempController: UIViewController?
    /// 下一个临时控制器 允许在动画过程中提前终止上一个动画并展示新的动画切换效果
    private(set) var nextTempController: UIViewController?
    
    /// 拖拽手势
    private lazy var pan: UIPanGestureRecognizer = {
        let tmp = UIPanGestureRecognizer.init(target: self, action: #selector(touchPan(_:)))
        tmp.maximumNumberOfTouches = 1
        tmp.delegate = self
        return tmp
    }()
    /// 点击手势
    private lazy var tap: UITapGestureRecognizer = {
        let tmp = UITapGestureRecognizer.init(target: self, action: #selector(touchTap(_:)))
        tmp.delegate = self
        return tmp
    }()

    private enum FlipDirection {
    case left
    case right
    }
    
    private enum AnimationKey: String {
    case clickLeft
    case clickRight
    case gestureLeft
    case gestureRight
    case cancelLeft
    case cancelRight
    }
    
    /// 手势触发点在左边 辨认方向 左边拿上一个控制器 右边拿下一个控制器
    private var flipDirection: FlipDirection?
    /// 本次拖拽手势是否响应
    private var isPan: Bool = false
    /// 手势是否重新开始识别
    private var isPanBegin: Bool = false
    /// 即将停止动画展示
    private var isStopingAnimation: Bool = false
    /// 手势翻页是否成功
    private var gestureSuccess: Bool = false
    
    /// 移动中的触摸位置
    private var moveTouchPoint: CGPoint = .zero
    /// 移动中的差值
    private var moveSpaceX: CGFloat = 0
    
    private var kViewWidth: CGFloat { self.view.bounds.size.width }
    private var kViewHeight: CGFloat { self.view.bounds.size.height }
    /// 动画时间
    private let animateDuration: TimeInterval = 0.3
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.didInit()
    }
    
    private func didInit() {
        self.view.backgroundColor = .clear
        // 添加手势
        self.view.addGestureRecognizer(self.pan)
        self.view.addGestureRecognizer(self.tap)
    }
    
    @objc private func touchTap(_ tap: UITapGestureRecognizer) {
        // 正在动画
        guard !isAnimateChange else { return }
        // 设置正在动画中
        isAnimateChange = true
        let touchPoint = tap.location(in: tap.view)
        // 获取将要显示的控制器
        tempController = getTapGesture(with: touchPoint)
        // 添加
        addController(tempController)
        // 手势结束
        gestureSuccess(true, animated: true)
    }
    
    @objc private func touchPan(_ pan: UIPanGestureRecognizer) {
        delegate?.touchPan(pan)
        
        // 用于辨别方向
        let transPoint = pan.translation(in: pan.view)
        // 用于计算位置
        let touchPoint = pan.location(in: pan.view)
        // 比较获取差值
        if moveTouchPoint != .zero, pan.state == .began || pan.state == .changed {
            moveSpaceX = touchPoint.x - moveTouchPoint.x
        }
        // 记录位置
        moveTouchPoint = touchPoint
        
        switch pan.state {
        case .began:
            // 正在动画
            if isAnimateChange, let direction = flipDirection {
                animateCancel(direction)
                nextTempController = getPanController(with: transPoint)
                return
            }
            // 设置正在动画中
            isAnimateChange = true
            isPan = true
            isPanBegin = true
        case .changed:
            guard isPan else { return }
            // 滚动有值了 不在向上或向下滑动判定区间内
            if abs(transPoint.x) > 0.01, abs(transPoint.y) > 0.01, abs(transPoint.x) / abs(transPoint.y) > 0.258 {
                // 获取将要显示的控制器 每次手势拖拽期间只获取一次
                if isPanBegin {
                    isPanBegin = false
                    // 获取将要显示的控制器
                    tempController = getPanController(with: transPoint)
                    // 添加
                    addController(tempController)
                }
                // 移动视图
                if currentController != nil, tempController != nil {
                    if flipDirection == .left {
                        tempController?.view.frame = CGRect(x: max(0, transPoint.x) - kViewWidth, y: 0, width: kViewWidth, height: kViewHeight)
                    } else if flipDirection == .right {
                        currentController?.view.frame = CGRect(x: transPoint.x > 0 ? 0 : transPoint.x, y: 0, width: kViewWidth, height: kViewHeight)
                    }
                }
            }
        default: // 手势结束
            // 清空记录
            defer {
                isPan = false
                isPanBegin = false
                moveTouchPoint = .zero
                moveSpaceX = 0
            }
            guard isPan else { return }
            // 判断是否是向上或向下滑动
            if tempController == nil, abs(transPoint.y) > 0.01, abs(transPoint.x) / abs(transPoint.y) <= 0.258 {
                tempController = getBelowController()
                // 添加
                addController(tempController)
                // 动画
                if tempController != nil {
                    gestureSuccess(true, animated: true)
                } else {
                    isAnimateChange = false
                }
            } else {
                // 正常手势动画
                if tempController != nil {
                    var isSuccess = true
                    if flipDirection == .left {
                        if moveSpaceX < 0 {
                            isSuccess = false
                        }
                    } else if flipDirection == .right {
                        if moveSpaceX > 0 {
                            isSuccess = false
                        }
                    }
                    // 手势结束
                    gestureSuccess(isSuccess, animated: true)
                } else {
                    isAnimateChange = false
                }
            }
        }
    }
    
    private func clickSuccess(_ isSuccess: Bool, animated: Bool) {
        guard let currentVC = currentController, let tempVC = tempController else { return }
        if flipDirection == .left {
            if animated {
                // 解决快速点击动画阻塞问题，不能使用block方式
                UIView.beginAnimations(AnimationKey.clickLeft.rawValue, context: nil)
                UIView.setAnimationDuration(animateDuration)
                UIView.setAnimationCurve(.easeOut)
                UIView.setAnimationDelegate(self)
                UIView.setAnimationDidStop(#selector(animationDidStop(_:)))
                if isSuccess {
                    tempVC.view.frame = CGRect(x: 0, y: 0, width: kViewWidth, height: kViewHeight)
                } else {
                    tempVC.view.frame = CGRect(x: -kViewWidth, y: 0, width: kViewWidth, height: kViewHeight)
                }
                UIView.commitAnimations()
            } else {
                if isSuccess {
                    tempVC.view.frame = CGRect(x: 0, y: 0, width: kViewWidth, height: kViewHeight)
                } else {
                    tempVC.view.frame = CGRect(x: -kViewWidth, y: 0, width: kViewWidth, height: kViewHeight)
                }
                animateSuccess(isSuccess)
            }
        } else if flipDirection == .right {
            if animated {
                // 解决快速点击动画阻塞问题，不能使用block方式
                UIView.beginAnimations(AnimationKey.clickRight.rawValue, context: nil)
                UIView.setAnimationDuration(animateDuration)
                UIView.setAnimationCurve(.easeOut)
                UIView.setAnimationDelegate(self)
                UIView.setAnimationDidStop(#selector(animationDidStop(_:)))
                if isSuccess {
                    currentVC.view.frame = CGRect(x: -kViewWidth, y: 0, width: kViewWidth, height: kViewHeight)
                } else {
                    currentVC.view.frame = CGRect(x: 0, y: 0, width: kViewWidth, height: kViewHeight)
                }
                UIView.commitAnimations()
            } else {
                if isSuccess {
                    currentVC.view.frame = CGRect(x: -kViewWidth, y: 0, width: kViewWidth, height: kViewHeight)
                } else {
                    currentVC.view.frame = CGRect(x: 0, y: 0, width: kViewWidth, height: kViewHeight)
                }
                animateSuccess(isSuccess)
            }
        }
    }
    
    private func gestureSuccess(_ isSuccess: Bool, animated: Bool) {
        self.gestureSuccess = isSuccess
        guard let currentVC = currentController, let tempVC = tempController else { return }
        if flipDirection == .left {
            if animated {
                // 解决快速点击动画阻塞问题，不能使用block方式
                UIView.beginAnimations(AnimationKey.gestureLeft.rawValue, context: nil)
                UIView.setAnimationDuration(animateDuration)
                UIView.setAnimationCurve(.easeOut)
                UIView.setAnimationDelegate(self)
                UIView.setAnimationDidStop(#selector(animationDidStop(_:)))
                if isSuccess {
                    tempVC.view.frame = CGRect(x: 0, y: 0, width: kViewWidth, height: kViewHeight)
                } else {
                    tempVC.view.frame = CGRect(x: -kViewWidth, y: 0, width: kViewWidth, height: kViewHeight)
                }
                UIView.commitAnimations()
            } else {
                if isSuccess {
                    tempVC.view.frame = CGRect(x: 0, y: 0, width: kViewWidth, height: kViewHeight)
                } else {
                    tempVC.view.frame = CGRect(x: -kViewWidth, y: 0, width: kViewWidth, height: kViewHeight)
                }
                animateSuccess(isSuccess)
            }
        } else if flipDirection == .right {
            if animated {
                // 解决快速点击动画阻塞问题，不能使用block方式
                UIView.beginAnimations(AnimationKey.gestureRight.rawValue, context: nil)
                UIView.setAnimationDuration(animateDuration)
                UIView.setAnimationCurve(.easeOut)
                UIView.setAnimationDelegate(self)
                UIView.setAnimationDidStop(#selector(animationDidStop(_:)))
                if isSuccess {
                    currentVC.view.frame = CGRect(x: -kViewWidth, y: 0, width: kViewWidth, height: kViewHeight)
                } else {
                    currentVC.view.frame = CGRect(x: 0, y: 0, width: kViewWidth, height: kViewHeight)
                }
                UIView.commitAnimations()
            } else {
                if isSuccess {
                    currentVC.view.frame = CGRect(x: -kViewWidth, y: 0, width: kViewWidth, height: kViewHeight)
                } else {
                    currentVC.view.frame = CGRect(x: 0, y: 0, width: kViewWidth, height: kViewHeight)
                }
                animateSuccess(isSuccess)
            }
        }
    }
    
    /// 根据手势触发的位置获取控制器
    private func getTapGesture(with touchPoint: CGPoint) -> UIViewController? {
        if touchPoint.x < kViewWidth / 2 { // 左边
            // 获取上一个显示控制器
            flipDirection = .left
            if let vc = dataSource?.coverController(self, getAboveController: self.currentController) {
                return vc
            }
        } else if touchPoint.x > kViewWidth / 2 { // 右边
            // 获取下一个显示控制器
            flipDirection = .right
            if let vc = dataSource?.coverController(self, getBelowController: self.currentController) {
                return vc
            }
        }
        flipDirection = nil
        return nil
    }
    
    /// 根据手势触发的位置获取控制器
    private func getPanController(with touchPoint: CGPoint) -> UIViewController? {
        if touchPoint.x > 0 { // 左边
            // 获取上一个显示控制器
            flipDirection = .left
            if let vc = dataSource?.coverController(self, getAboveController: self.currentController) {
                return vc
            }
        } else if touchPoint.x < 0 { // 右边
            // 获取下一个显示控制器
            flipDirection = .right
            if let vc = dataSource?.coverController(self, getBelowController: self.currentController) {
                return vc
            }
        }
        flipDirection = nil
        return nil
    }
    
    /// 直接获取下一个控制器
    private func getBelowController() -> UIViewController? {
        // 获取下一个显示控制器
        if let vc = dataSource?.coverController(self, getBelowController: self.currentController) {
            flipDirection = .right
            return vc
        }
        flipDirection = nil
        return nil
    }
    
    /// 添加控制器
    private func addController(_ controller: UIViewController?) {
        guard let controller = controller else { return }
        addChild(controller)
        if flipDirection == .left { // 左边
            self.view.addSubview(controller.view)
            controller.view.frame = CGRect(x: -kViewWidth, y: 0, width: kViewWidth, height: kViewHeight)
        } else { // 右边
            if let currentVC = currentController { // 有值
                self.view.insertSubview(controller.view, belowSubview: currentVC.view)
            } else { // 没值
                self.view.addSubview(controller.view)
            }
            controller.view.frame = CGRect(x: 0, y: 0, width: kViewWidth, height: kViewHeight)
        }
        // 添加阴影
        setShadowController(controller)
    }
    
    /// 给控制器添加阴影
    private func setShadowController(_ controller: UIViewController) {
        controller.view.layer.shadowPath = UIBezierPath(rect: controller.view.bounds).cgPath
        controller.view.layer.shadowColor = UIColor.black.cgColor // 阴影颜色
        controller.view.layer.shadowOffset = CGSize(width: 0, height: 0) // 偏移距离
        controller.view.layer.shadowOpacity = 0.5 // 不透明度
        controller.view.layer.shadowRadius = 10.0 // 半径
    }
    
    /// 动画结束
    private func animateSuccess(_ isSuccess: Bool) {
        if isSuccess, let vc = tempController {
            currentController?.view.removeFromSuperview()
            currentController?.removeFromParent()
            currentController = vc
            tempController = nil
        } else {
            currentController?.view.frame = CGRect(x: 0, y: 0, width: kViewWidth, height: kViewHeight)
            tempController?.view.removeFromSuperview()
            tempController?.removeFromParent()
            tempController = nil
        }
        isAnimateChange = false
        delegate?.coverController(self, currentController: currentController, finish: isSuccess)
    }

    private func animateCancel(_ flipDirection: FlipDirection) {
        switch flipDirection {
        case .left:
            if let tempVC = tempController {
                isStopingAnimation = true
                tempVC.view.layer.removeAllAnimations()
                UIView.beginAnimations(AnimationKey.cancelLeft.rawValue, context: nil)
                UIView.setAnimationBeginsFromCurrentState(true)
                UIView.setAnimationDuration(0.1)
                UIView.setAnimationCurve(.easeOut)
                tempVC.view.frame = CGRect(x: 0, y: 0, width: kViewWidth, height: kViewHeight)
                UIView.commitAnimations()
            }
        case .right:
            if let currentVC = currentController {
                isStopingAnimation = true
                currentVC.view.layer.removeAllAnimations()
                UIView.beginAnimations(AnimationKey.cancelRight.rawValue, context: nil)
                UIView.setAnimationBeginsFromCurrentState(true)
                UIView.setAnimationDuration(0.1)
                UIView.setAnimationCurve(.easeOut)
                currentVC.view.frame = CGRect(x: -kViewWidth, y: 0, width: kViewWidth, height: kViewHeight)
                UIView.commitAnimations()
            }
        }
    }
    
    @objc private func animationDidStop(_ anim: String) {
        var isSuccess: Bool = true
        if anim == AnimationKey.clickLeft.rawValue || anim == AnimationKey.clickRight.rawValue {
            isSuccess = true
        } else if anim == AnimationKey.gestureLeft.rawValue || anim == AnimationKey.gestureRight.rawValue {
            isSuccess = gestureSuccess
        }
        if isStopingAnimation {
            isStopingAnimation = false
            animateSuccess(isSuccess)
            if let nextVC = nextTempController {
                setController(nextVC, animated: true, isAbove: flipDirection == .left)
                nextTempController = nil
            }
        } else {
            animateSuccess(isSuccess)
        }
    }
    
    deinit {
        debugPrint(description + #function)
    }
}

extension ZKCoverController {
    
    /// 设置显示控制器
    func setController(_ controller: UIViewController, animated: Bool = false, isAbove: Bool = true) {
        if animated, currentController != nil { // 需要动画 允许手势动画 同时有根控制器了
            // 正在动画
            let lastDirection = flipDirection
            flipDirection = isAbove ? .left : .right
            if isAnimateChange, let direction = lastDirection {
                animateCancel(direction)
                nextTempController = controller
                return
            }
            isAnimateChange = true
            // 记录
            tempController = controller
            // 添加
            addController(controller)
            // 手势结束
            clickSuccess(true, animated: true)
        } else {
            // 添加
            addController(controller)
            // 修改frame
            controller.view.frame = self.view.bounds
            // 当前控制器有值 进行删除
            currentController?.view.removeFromSuperview()
            currentController?.removeFromParent()
            // 赋值记录
            currentController = controller
        }
    }
    
}

extension ZKCoverController: UIGestureRecognizerDelegate {
    
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if let shouldBegin = delegate?.coverController(self, gestureRecognizerShouldBegin: gestureRecognizer) {
            return shouldBegin
        }
        return true
    }
    
}
