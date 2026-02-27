// pages/index/index.js
Page({
  data: {
    devices: [],
    loading: true,
    error: null
  },

  onLoad() {
    this.loadUserDevices()
  },

  // 新增：页面显示时检查是否需要刷新（从添加设备页返回时触发）
  onShow() {
    if (getApp().globalData.needRefreshDevices) {
      getApp().globalData.needRefreshDevices = false; // 用完立即清除
      console.log('首页检测到需要刷新设备列表（从添加设备页返回）')
      this.refresh()
    }
  },

  loadUserDevices() {
    this.setData({ loading: true, error: null })

    wx.cloud.callFunction({
      name: 'onenetGateway',
      data: {
        action: 'onenet',
        subAction: 'getUserDevices'
      }
    })
    .then(res => {
      const result = res.result

      if (result.code === 200) {
        const safeDevices = (result.data || []).map(d => ({
          ...d,
          state: d.state || {},
          connectType: d.connectType || 'wifi'
        }))

        this.setData({
          devices: safeDevices,
          loading: false
        })

      } else {
        this.setData({
          error: result.msg || '获取设备失败',
          loading: false
        })
      }
    })
    .catch(() => {
      this.setData({
        error: '网络错误，请稍后重试',
        loading: false
      })
    })
  },

  goDetail(e) {
    const device = e.detail   // 关键改这里
  
    if (!device || !device.deviceId) {
      console.error('设备数据异常', device)
      return
    }
  
    wx.navigateTo({
      url: `/pages/device/device?deviceId=${device.deviceId}`
    })
  },
  
  goAddDevice() {
    console.log('点击了添加设备按钮')   // ← 加这行，用于调试
    wx.navigateTo({
      url: '/pages/add-device/add-device',
      success: () => {
        console.log('跳转成功')
      },
      fail: (err) => {
        console.error('跳转失败', err)
      }
    })
  },

  // 接收设备卡片组件发出的 refresh 事件（重命名/删除后）
  onDeviceRefresh() {
    console.log('收到设备卡片 refresh 事件')
    this.refresh()
  },

  // 统一刷新方法（可被 onShow、onDeviceRefresh 等调用）
  refresh() {
    console.log('执行 refresh，重新加载设备列表')
    this.loadUserDevices()
  }
})