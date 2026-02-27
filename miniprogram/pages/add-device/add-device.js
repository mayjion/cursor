Page({
  data: {
    productId: '',
    deviceName: '',
    loading: false,
    errorMsg: '',
    successMsg: ''
  },

  // 扫码添加
  scanQrCode() {
    wx.scanCode({
      onlyFromCamera: false,  // 允许相册
      scanType: ['qrCode'],   // 只扫二维码
      success: (res) => {
        console.log('扫码结果：', res);
        const result = res.result;

        // 假设二维码内容是 JSON 字符串，例如：{"productId":"s9ASuUqu0y","deviceName":"ACA7048E8364"}
        // 或纯文本：productId=s9ASuUqu0y&deviceName=ACA7048E8364
        try {
          // 尝试作为 JSON 解析（推荐二维码内容用 JSON）
          const data = JSON.parse(result);
          this.setData({
            productId: data.productId || '',
            deviceName: data.deviceName || data.mac || ''
          });
          this.addDevice();  // 自动提交
        } catch (e) {
          // 不是 JSON，尝试 key=value 格式
          const params = this.parseQueryString(result);
          this.setData({
            productId: params.productId || '',
            deviceName: params.deviceName || params.mac || ''
          });
          if (this.data.productId && this.data.deviceName) {
            this.addDevice();  // 自动提交
          } else {
            wx.showToast({ title: '二维码格式不正确', icon: 'none' });
          }
        }
      },
      fail: (err) => {
        console.error('扫码失败', err);
        wx.showToast({ title: '扫码取消或失败', icon: 'none' });
      }
    });
  },

  // 解析 key=value 字符串
  parseQueryString(str) {
    const obj = {};
    str.split('&').forEach(pair => {
      const [key, value] = pair.split('=');
      if (key && value) obj[key] = decodeURIComponent(value);
    });
    return obj;
  },

  onProductIdInput(e) {
    this.setData({ productId: e.detail.value.trim() });
  },

  onDeviceNameInput(e) {
    this.setData({ deviceName: e.detail.value.trim() });
  },

// add-device.js（只展示改动部分，其他保持不变）

  addDevice() {
    const { productId, deviceName } = this.data;
    if (!productId || !deviceName) {
      wx.showToast({ title: '信息不完整', icon: 'none' });
      return;
    }

    this.setData({ loading: true, errorMsg: '', successMsg: '' });

    wx.cloud.callFunction({
      name: 'onenetGateway',
      data: {
        action: 'onenet',
        subAction: 'addDevice',
        productId,
        deviceName
      }
    })
    .then(res => {
      console.log('添加设备返回：', res);
      const result = res.result || {};
      if (result.code === 200) {
        this.setData({ successMsg: '添加成功！', loading: false });
        wx.showToast({ title: '添加成功', icon: 'success' });

        // 关键改动：标记需要刷新首页列表
        getApp().globalData.needRefreshDevices = true;

        // 延迟返回首页，让 toast 显示完整
        setTimeout(() => {
          wx.navigateBack({
            delta: 1
          });
        }, 1200);  // 1.2秒后返回
      } else {
        this.setData({ 
          errorMsg: result.msg || '添加失败，请重试',
          loading: false 
        });
      }
    })
    .catch(err => {
      console.error('云函数调用失败', err);
      this.setData({ 
        errorMsg: '网络异常，请检查网络',
        loading: false 
      });
    });
  },

  // 返回上一页
  goBack() {
    wx.navigateBack();
  }
});