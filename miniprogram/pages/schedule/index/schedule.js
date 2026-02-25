Page({

  data: {
    productId: '',
    deviceName: '',
    taskList: []
  },

  onLoad(options) {

    this.setData({
      productId: options.productId,
      deviceName: options.deviceName
    })

    this.loadSchedule()
  },

  async loadSchedule(){

    const res = await wx.cloud.callFunction({
      name:'onenetGateway',
      data:{
        action:'onenet',
        subAction:'getProperty',
        productId:this.data.productId,
        deviceName:this.data.deviceName
      }
    })

    const schedule = res.result?.data?.schedule
    this.parseSchedule(schedule)
  },

  parseSchedule(schedule){

    if(!schedule){
      this.setData({ taskList: [] })
      return
    }

    let list=[]

    schedule.periods?.forEach(p=>{
      list.push({ desc:'周期任务' })
    })

    schedule.one_shot?.forEach(o=>{
      list.push({ desc:'单次任务' })
    })

    this.setData({ taskList:list })
  },

  addTask(){
    wx.showToast({ title:'这里做完整编辑UI', icon:'none' })
  }

})
