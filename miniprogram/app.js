// app.js
App({
  onLaunch() {
    // ===== 云开发初始化（新增）=====
    wx.cloud.init({
      env: 'cloud1-7gyi15j51f3efa3e', // 你的云环境 ID
      traceUser: true
    })

    // ===== 原有逻辑，保持不变 =====
    const logs = wx.getStorageSync('logs') || []
    logs.unshift(Date.now())
    wx.setStorageSync('logs', logs)

    wx.login({
      success: res => {
        // 这里以后可以把 res.code 传给云函数
        // 用来换 openid / sessionKey
      }
    })
  },

  globalData: {
    userInfo: null,
    needRefreshDevices: false
  }
})
