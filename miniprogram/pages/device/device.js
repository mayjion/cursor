Page({
  data: {
    deviceId: '',
    device: null,
    loading: true,
    error: null
  },

  onLoad(options) {
    if (!options || !options.deviceId) {
      this.setData({
        loading: false,
        error: '设备ID缺失'
      })
      return
    }

    this.setData({
      deviceId: options.deviceId
    })

    this.loadDeviceDetail()
  },

  loadDeviceDetail() {
    wx.cloud.callFunction({
      name: 'onenetGateway',
      data: {
        action: 'onenet',
        subAction: 'getDeviceDetail',
        deviceId: this.data.deviceId
      }
    })
    .then(res => {

      console.log('设备详情返回：', res)

      if (!res || !res.result) {
        this.setData({
          loading: false,
          error: '云函数返回异常'
        })
        return
      }

      const result = res.result

      if (result.code === 200 && result.data) {
        this.setData({
          device: result.data,
          loading: false
        })
      } else {
        this.setData({
          loading: false,
          error: result.msg || '获取设备详情失败'
        })
      }

    })
    .catch(err => {
      console.error('加载设备详情失败：', err)
      this.setData({
        loading: false,
        error: '网络异常'
      })
    })
  }
})
