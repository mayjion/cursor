Component({
  properties: {
    device: {
      type: Object,
      value: {},
      observer: function(newVal) {
        this.updateDisplayName(newVal)
        this.updateImageSrc(newVal)  // 新增：监听 device 变化时更新图片
      }
    }
  },

  data: {
    displayName: '未知设备',
    imgSrc: '/images/default-device.png'  // 默认占位图路径（本地优先）
  },

  lifetimes: {
    attached() {
      this.updateDisplayName(this.properties.device)
      this.updateImageSrc(this.properties.device)
    }
  },

  methods: {
    // 计算显示名称（原有）
    updateDisplayName(device) {
      let name = '未知设备'
      if (device) {
        name = device.alias || device.deviceName || '未知设备'
      }
      const truncated = name.length > 6 ? name.substring(0, 6) + '...' : name
      this.setData({ displayName: truncated })
    },


    updateImageSrc(device) {
      let src = '/images/default-device.png';
      if (device) {
        // 支持更多可能的字段名，增加鲁棒性
        src = device.cover || device.image || device.pic || device.thumbnail || device.imgUrl || device.picture || src;
      }
      this.setData({ imgSrc: src });
    },

    onImageError(e) {
      console.warn('设备图片加载失败:', e.detail.errMsg, 'deviceId:', this.properties.device?.deviceId);
      this.setData({
        imgSrc: '/images/default-device.png'
      });
    },

    // 点击卡片主体 → 进入详情页
    onTap() {
      console.log('卡片主体点击', this.properties.device)
      this.triggerEvent('tapdevice', this.properties.device)
    },

    // 点击右下角三个点 → 弹出操作菜单
    showActionSheet() {
      const device = this.properties.device
      if (!device || !device.deviceId) {
        wx.showToast({ title: '设备信息异常', icon: 'none' })
        return
      }

      wx.showActionSheet({
        itemList: ['重命名', '删除设备'],
        itemColor: '#000000',
        success: (res) => {
          const index = res.tapIndex
          if (index === 0) {
            this.renameDevice(device)
          } else if (index === 1) {
            this.unbindDevice(device)
          }
        },
        fail(res) {
          // 用户取消，不处理
        }
      })
    },

    // 重命名 alias
    renameDevice(device) {
      wx.showModal({
        title: '重命名设备',
        content: '',
        editable: true,
        placeholderText: device.alias || device.deviceName || '请输入新名称',
        success: (res) => {
          if (res.confirm && res.content && res.content.trim()) {
            const newAlias = res.content.trim()

            wx.cloud.callFunction({
              name: 'onenetGateway',
              data: {
                action: 'onenet',
                subAction: 'updateAlias',
                deviceId: device.deviceId,
                alias: newAlias
              }
            }).then(cfRes => {
              const result = cfRes.result || {}
              if (result.code === 200) {
                wx.showToast({ title: '重命名成功', icon: 'success' })
                this.triggerEvent('refresh')
              } else {
                wx.showToast({ title: result.msg || '操作失败', icon: 'none' })
              }
            }).catch(err => {
              console.error('重命名云函数调用失败', err)
              wx.showToast({ title: '网络异常', icon: 'none' })
            })
          }
        }
      })
    },

    // 解除绑定
    unbindDevice(device) {
      wx.showModal({
        title: '解除设备绑定',
        content: '确定要删除该设备吗？删除后你将无法控制它，但设备记录仍保留。',
        confirmColor: '#f44336',
        success: (res) => {
          if (res.confirm) {
            wx.cloud.callFunction({
              name: 'onenetGateway',
              data: {
                action: 'onenet',
                subAction: 'unbindDevice',
                deviceId: device.deviceId
              }
            }).then(cfRes => {
              const result = cfRes.result || {}
              if (result.code === 200) {
                wx.showToast({ title: '已解除绑定', icon: 'success' })
                this.triggerEvent('refresh')
              } else {
                wx.showToast({ title: result.msg || '操作失败', icon: 'none' })
              }
            }).catch(err => {
              console.error('解绑云函数调用失败', err)
              wx.showToast({ title: '网络异常', icon: 'none' })
            })
          }
        }
      })
    },

    // 快速切换继电器
    toggleRelay() {
      const device = this.properties.device
      if (!device.online) {
        wx.showToast({ title: '设备离线，无法操作', icon: 'none' })
        return
      }

      const currentState = device.state && device.state.relay1 || false
      const newState = !currentState

      // 乐观更新 UI
      this.setData({
        'device.state.relay1': newState
      })

      wx.cloud.callFunction({
        name: 'onenetGateway',
        data: {
          action: 'onenet',
          subAction: 'setProperty',
          productId: device.productId,
          deviceName: device.deviceName,
          params: {
            relay1: {
              value: newState
            }
          }
        }
      }).then(res => {
        const result = res.result || {}
        if (result.code !== 200) {
          // 失败回滚
          this.setData({
            'device.state.relay1': currentState
          })
          wx.showToast({ title: '操作失败，请重试', icon: 'none' })
        } else {
          wx.showToast({ title: newState ? '已开启' : '已关闭', icon: 'success' })
          this.triggerEvent('refresh')
        }
      }).catch(err => {
        this.setData({
          'device.state.relay1': currentState
        })
        wx.showToast({ title: '网络异常', icon: 'none' })
      })
    },

    onSwitchChange(e) {
      if (e.detail.value !== (this.properties.device.state && this.properties.device.state.relay1 || false)) {
        this.toggleRelay()
      }
    }
  }
})
